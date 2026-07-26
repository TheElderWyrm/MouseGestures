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
    /// Which validation path issued the stored key: `"hmac"` (this app's own
    /// offline scheme, `LicenseKey`) or `"lemonsqueezy"` (a real purchase,
    /// verified once online via `LemonSqueezyLicense`). Absent/unrecognized
    /// values are treated as `"hmac"` for back-compat with keys stored before
    /// this distinction existed.
    private let licenseTypeKey = "MGLicenseType"
    /// The Lemon Squeezy activation instance id for this Mac, so deactivation
    /// can free the slot on their side too. Only set for `"lemonsqueezy"` keys.
    private let licenseInstanceIdKey = "MGLicenseInstanceID"

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

        // Developer tools are Pro-only (see canUseDeveloperTools), so force
        // developer mode off when the license drops to free/expired. The flag
        // actually lives in Configuration (persisted to gestures.json) and is
        // read by DevActionRunnerHook et al.; the previous code wrote a
        // UserDefaults key ("MGDeveloperModeEnabled") that nothing ever reads,
        // so developer mode stayed enabled after a trial expired — leaving the
        // Pro-only dev hook active for a free user. Route through the canonical
        // setter so the change is persisted and the "developerModeChanged"
        // observers (tab visibility) update live. Guarded to fire only on a
        // real on→off transition rather than on every refresh.
        if (newStatus == .free || newStatus == .expired),
           DeveloperModeToggleService.shared.isEnabled() {
            DeveloperModeToggleService.shared.setEnabled(false)
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

    /// True if a valid Pro license key is currently stored. Lemon Squeezy keys
    /// are trusted once activation has succeeded — see `activateLicense` —
    /// so this never needs network access; the app works fully offline after
    /// the first successful activation, same as the offline HMAC keys always have.
    public var hasValidLicense: Bool {
        guard let key = defaults.string(forKey: licenseKeyKey), !key.isEmpty else { return false }
        if defaults.string(forKey: licenseTypeKey) == "lemonsqueezy" { return true }
        return LicenseKey.isValid(key)
    }

    /// The stored license key formatted for display, or `nil` if none is stored.
    /// Lemon Squeezy keys are its own UUID format, shown as-is — `LicenseKey.format`
    /// would mangle them, since it assumes this app's own dash-grouped scheme.
    public var storedLicenseKeyDisplay: String? {
        guard let key = defaults.string(forKey: licenseKeyKey), !key.isEmpty else { return nil }
        if defaults.string(forKey: licenseTypeKey) == "lemonsqueezy" { return key }
        return LicenseKey.format(key)
    }

    /// Result of an activation attempt, distinguishing the reasons a key can
    /// fail so the UI can show something more useful than a single generic message.
    public enum ActivationResult: Equatable {
        case success
        case invalidKey
        case activationLimitReached
        case networkError
    }

    /// Validates and, if valid, stores a license key to unlock Pro.
    ///
    /// Tries this app's own offline HMAC scheme first (instant, no network —
    /// used for manually-issued support/comp keys). Anything else is treated
    /// as a real Lemon Squeezy purchase key and verified once online via the
    /// License API; on success the result is cached locally (`hasValidLicense`
    /// above), so this is the only network call activation ever needs.
    public func activateLicense(_ rawKey: String, completion: @escaping (ActivationResult) -> Void) {
        let normalized = LicenseKey.normalize(rawKey)
        if LicenseKey.isValid(normalized) {
            defaults.set(normalized, forKey: licenseKeyKey)
            defaults.set("hmac", forKey: licenseTypeKey)
            defaults.removeObject(forKey: licenseInstanceIdKey)
            refreshLicenseStatus()
            completion(.success)
            return
        }

        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            completion(.invalidKey)
            return
        }

        let instanceName = Host.current().localizedName ?? "Mac"
        let request = LemonSqueezyLicense.activateRequest(licenseKey: trimmedKey, instanceName: instanceName)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard error == nil, let data = data,
                      let response = try? LemonSqueezyLicense.parseActivateResponse(data) else {
                    completion(.networkError)
                    return
                }
                guard response.activated, let instance = response.instance else {
                    if (response.error ?? "").localizedCaseInsensitiveContains("activation limit") {
                        completion(.activationLimitReached)
                    } else {
                        completion(.invalidKey)
                    }
                    return
                }
                self.defaults.set(trimmedKey, forKey: self.licenseKeyKey)
                self.defaults.set("lemonsqueezy", forKey: self.licenseTypeKey)
                self.defaults.set(instance.id, forKey: self.licenseInstanceIdKey)
                self.refreshLicenseStatus()
                completion(.success)
            }
        }.resume()
    }

    /// Removes any stored license key and reverts to trial/free status.
    /// For a Lemon Squeezy key, also best-effort deactivates the instance on
    /// their side so the activation slot is freed — but local deactivation
    /// never waits on (or depends on) that call succeeding, since the user's
    /// choice to deactivate this Mac shouldn't require being online.
    public func deactivateLicense() {
        if defaults.string(forKey: licenseTypeKey) == "lemonsqueezy",
           let key = defaults.string(forKey: licenseKeyKey),
           let instanceId = defaults.string(forKey: licenseInstanceIdKey) {
            let request = LemonSqueezyLicense.deactivateRequest(licenseKey: key, instanceId: instanceId)
            URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
        }
        defaults.removeObject(forKey: licenseKeyKey)
        defaults.removeObject(forKey: licenseTypeKey)
        defaults.removeObject(forKey: licenseInstanceIdKey)
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
        defaults.removeObject(forKey: licenseTypeKey)
        defaults.removeObject(forKey: licenseInstanceIdKey)
        defaults.set(true, forKey: "MGFootprintForcedFree") // Optional indicator
        forceFreeMode = true // This will trigger a refresh via didSet

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
