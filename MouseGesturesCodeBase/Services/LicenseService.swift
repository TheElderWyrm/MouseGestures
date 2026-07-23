import Foundation
import Cocoa
import UserNotifications

// `LicenseStatus` and the pure trial/gating math live in `LicenseLogic.swift`,
// and offline license-key validation lives in `LicenseKey.swift`, so both can be
// unit-tested without UserDefaults/UI dependencies. Pro is unlocked by a locally
// verified license key (see `LicenseKey`) — the StoreKit IAP path was removed for
// direct (non–App-Store) distribution.

/// Service that manages application licensing and feature gating
public class LicenseService: ObservableObject {

    // MARK: - Singleton

    public static let shared = LicenseService()

    // MARK: - Constants

    private let trialDurationDays = LicenseLogic.trialDurationDays
    private let firstLaunchKey = "MGFirstLaunchDate"
    private let licenseKeyKey = "MGLicenseKey"

    // MARK: - Properties

    @Published private(set) var status: LicenseStatus = .free
    @Published private(set) var trialDaysRemaining: Int = 0
    @Published public var forceFreeMode: Bool = false {
        didSet {
            refreshLicenseStatus()
        }
    }

    private let defaults = UserDefaults.standard
    private let lastNotifiedThresholdKey = "MGLastNotifiedTrialThreshold"

    private var checkTimer: Timer?
    private let lastCheckDateKey = "MGLastTrialCheckDate"
    /// Monotonic high-water mark of the latest date we've ever observed. Used to
    /// resist trial bypass-by-clock-rollback: if the system clock is set back
    /// before `firstLaunch` (or before the last seen date), the trial would
    /// otherwise reset to "more than 30 days remaining". We clamp `now` to
    /// never go below this mark so a backwards clock can't extend the trial.
    private let highWaterMarkDateKey = "MGTrialHighWaterMarkDate"
    // Suppresses the initial refresh at launch from firing a "trial expired"
    // notification before the UI is up; re-enabled immediately after.
    private var notificationsEnabled = false

    /// Returns `now` clamped to the persisted high-water-mark, then advances
    /// the mark. Guards against the user setting the system clock backwards to
    /// extend or reset the trial window. Offline-only defense (not airtight —
    /// a user who deletes this UserDefaults key still wins), but it closes the
    /// trivial `defaults write` / System Preferences clock-rollback path.
    private func clampedNow() -> Date {
        let now = Date()
        let lastMark = defaults.object(forKey: highWaterMarkDateKey) as? Date ?? .distantPast
        // If the clock was rolled back, keep using the last-seen (later) date.
        let effective = now > lastMark ? now : lastMark
        if effective > lastMark {
            defaults.set(effective, forKey: highWaterMarkDateKey)
        }
        return effective
    }

    // MARK: - Initialization

    private init() {
        refreshLicenseStatus() // Silent: notificationsEnabled is false during first launch refresh
        notificationsEnabled = true

        // Start periodic check timer (every hour to be safe, but checks date)
        startCheckTimer()
    }

    deinit {
        checkTimer?.invalidate()
    }

    private func startCheckTimer() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.performDailyCheck()
        }
    }

    private func performDailyCheck() {
        let now = clampedNow()
        let lastCheck = defaults.object(forKey: lastCheckDateKey) as? Date ?? .distantPast

        if !Calendar.current.isDate(now, inSameDayAs: lastCheck) {
            notificationsEnabled = true // Safe to notify after first-launch refresh
            refreshLicenseStatus()
            defaults.set(now, forKey: lastCheckDateKey)
        }
    }

    // MARK: - Public API

    /// Refresh the license status from stored settings
    public func refreshLicenseStatus() {
        // Handle forced free mode for testing
        if forceFreeMode {
            updateStatus(.free, remaining: 0)
            return
        }

        // Check for a locally stored, offline-verified Pro license key
        if hasValidLicense {
            updateStatus(.pro, remaining: 0)
            return
        }

        // Check trial status
        if let firstLaunch = defaults.object(forKey: firstLaunchKey) as? Date {
            let result = LicenseLogic.trialStatus(firstLaunch: firstLaunch,
                                                  now: clampedNow(),
                                                  durationDays: trialDurationDays)
            updateStatus(result.status, remaining: result.remaining)
        } else {
            // First launch - start trial
            let now = clampedNow()
            defaults.set(now, forKey: firstLaunchKey)
            updateStatus(.trial, remaining: trialDurationDays)
        }
    }

    private func updateStatus(_ newStatus: LicenseStatus, remaining: Int) {
        let oldStatus = self.status
        let oldRemaining = self.trialDaysRemaining

        self.status = newStatus
        self.trialDaysRemaining = remaining

        // Automatically disable developer mode if in free mode
        if newStatus == .free || newStatus == .expired {
            UserDefaults.standard.set(false, forKey: "MGDeveloperModeEnabled")
        }

        if oldStatus != newStatus || remaining != oldRemaining {
            checkTrialThresholds(status: newStatus, remaining: remaining)

            NotificationCenter.default.post(
                name: NSNotification.Name("LicenseStatusChanged"),
                object: self
            )
        }
    }

    private func checkTrialThresholds(status: LicenseStatus, remaining: Int) {
        guard notificationsEnabled else { return }
        // Only notify for trial or just expired
        guard (status == .trial || status == .expired) && !hasValidLicense else { return }

        let thresholds = [3, 1, 0]
        let currentThreshold = status == .expired ? 0 : remaining

        guard thresholds.contains(currentThreshold) else { return }

        // Only notify once per threshold per day to prevent spam
        let lastNotified = defaults.integer(forKey: lastNotifiedThresholdKey)
        let lastDate = defaults.object(forKey: "MGLastNotifiedDate") as? Date ?? .distantPast

        if lastNotified == currentThreshold && Calendar.current.isDateInToday(lastDate) && status != .expired {
            // For expiration (0), we might want to show it once on the day it happens
            return
        }

        // Special case: if it just expired (0), and we already notified for 0 today, don't spam
        if currentThreshold == 0 && lastNotified == 0 && Calendar.current.isDateInToday(lastDate) {
            return
        }

        if currentThreshold == 0 {
            NotificationCenter.default.post(name: .trialDidExpire, object: nil)
        }

        sendExpirationNotification(daysRemaining: currentThreshold)

        defaults.set(currentThreshold, forKey: lastNotifiedThresholdKey)
        defaults.set(Date(), forKey: "MGLastNotifiedDate")
    }

    private func sendExpirationNotification(daysRemaining: Int) {
        // If Pro is already unlocked, don't send anything
        if hasValidLicense { return }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = "TRIAL_EXPIRATION"

        if daysRemaining > 0 {
            content.title = "MouseGestures Pro Trial Ending"
            content.body = "Your trial expires in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s"). Upgrade now to keep all features."
        } else {
            content.title = "MouseGestures Pro Trial Expired"
            content.body = "Your trial has expired. Upgrade to continue using advanced features."
        }

        content.userInfo = ["daysRemaining": daysRemaining]
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.mousegestures.trial.expiration.\(daysRemaining)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                log.log("Failed to send trial notification: \(error)")
            }
        }
    }

    /// Returns true if the current license allows Pro features
    public var isPro: Bool {
        return LicenseLogic.allowsProFeatures(status)
    }

    /// Returns true if the app is currently in trial mode
    public var isTrial: Bool {
        return status == .trial
    }

    // MARK: - Offline License Activation

    /// True if a valid Pro license key is currently stored.
    public var hasValidLicense: Bool {
        guard let key = defaults.string(forKey: licenseKeyKey), !key.isEmpty else { return false }
        return LicenseKey.isValid(key)
    }

    /// The stored license key formatted for display, or `nil` if none is stored.
    public var storedLicenseKeyDisplay: String? {
        guard let key = defaults.string(forKey: licenseKeyKey), !key.isEmpty else { return nil }
        return LicenseKey.format(key)
    }

    /// Validates and, if valid, stores a license key to unlock Pro offline.
    /// - Returns: `true` if the key was accepted and Pro was unlocked; `false` if invalid.
    @discardableResult
    public func activateLicense(_ rawKey: String) -> Bool {
        let normalized = LicenseKey.normalize(rawKey)
        guard LicenseKey.isValid(normalized) else { return false }
        // Storing forceFreeMode wins over a key only while explicitly set for testing.
        defaults.set(normalized, forKey: licenseKeyKey)
        refreshLicenseStatus()
        return true
    }

    /// Removes any stored license key and reverts to trial/free status.
    public func deactivateLicense() {
        defaults.removeObject(forKey: licenseKeyKey)
        refreshLicenseStatus()
    }

    /// Reset the trial (for testing purposes)
    public func resetTrial() {
        defaults.removeObject(forKey: firstLaunchKey)
        defaults.removeObject(forKey: lastNotifiedThresholdKey)
        defaults.removeObject(forKey: "MGLastNotifiedDate")
        defaults.removeObject(forKey: "MGFootprintForcedFree")
        forceFreeMode = false
        refreshLicenseStatus()
    }

    /// Forces the trial to start today (for testing purposes)
    public func startTrial() {
        defaults.set(Date(), forKey: firstLaunchKey)
        defaults.removeObject(forKey: lastNotifiedThresholdKey)
        defaults.removeObject(forKey: "MGLastNotifiedDate")
        defaults.removeObject(forKey: "MGFootprintForcedFree")
        forceFreeMode = false
        refreshLicenseStatus()
    }

    /// Forces the trial to expire (for testing purposes)
    public func expireTrial() {
        // Set first launch date to 31 days ago
        let expiredDate = Calendar.current.date(byAdding: .day, value: -(trialDurationDays + 1), to: Date())
        defaults.set(expiredDate, forKey: firstLaunchKey)
        refreshLicenseStatus()
    }

    /// Removes any Pro license (for testing purposes)
    public func removeProLicense() {
        // Clear trial, stored license key, and pro indicators
        defaults.removeObject(forKey: firstLaunchKey)
        defaults.removeObject(forKey: licenseKeyKey)
        defaults.set(true, forKey: "MGFootprintForcedFree") // Optional indicator
        forceFreeMode = true // This will trigger a refresh via didSet

        // If there were other persistence keys for pro status, clear them here.

        NotificationCenter.default.post(
            name: NSNotification.Name("LicenseStatusChanged"),
            object: self
        )
    }

    // MARK: - Feature Gating

    /// Whether multiple profiles are allowed
    public var canUseMultipleProfiles: Bool {
        return isPro
    }

    /// Whether advanced targeting (app-specific profiles) is allowed
    public var canUseAdvancedTargeting: Bool {
        return isPro
    }

    /// Whether advanced actions (automation, plugins) are allowed
    public var canUseAdvancedActions: Bool {
        return isPro
    }

    /// Whether developer tools are allowed
    public var canUseDeveloperTools: Bool {
        return isPro
    }

    /// Check if a specific action identifier is allowed under the current license
    public func isActionAllowed(_ identifier: String) -> Bool {
        if isPro { return true }

        // Use the plugin manager to check if this specific action is advanced or external
        if let (plugin, action) = PluginManager.shared.getAction(identifier: identifier) {
            // Advanced plugins or actions are Pro-only
            if plugin.isAdvanced || action.isAdvanced { return false }

            // External (third-party) plugins are Pro-only
            if plugin.isExternal { return false }

            // Otherwise it's a basic built-in action
            return true
        }

        // Fallback for hardcoded core prefixes if plugin isn't loaded yet
        let corePrefixes = [
            "com.mousegestures.core.system",
            "com.mousegestures.core.media",
            "com.mousegestures.core.window",
            "com.mousegestures.core.app"
        ]

        return corePrefixes.contains { identifier.hasPrefix($0) }
    }
}

extension Notification.Name {
    public static let trialDidExpire = Notification.Name("com.mousegestures.trialDidExpire")
}
