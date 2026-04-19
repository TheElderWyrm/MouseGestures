import Foundation
import Cocoa
import UserNotifications

/// Represents the current license state of the application
public enum LicenseStatus: String, Codable {
    case trial = "Trial"
    case pro = "Pro"
    case expired = "Expired"
    case free = "Free"
}

/// Service that manages application licensing and feature gating
public class LicenseService: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = LicenseService()
    
    // MARK: - Constants
    
    private let trialDurationDays = 30
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
    
    // MARK: - Initialization
    
    private init() {
        refreshLicenseStatus()
        
        // Observe the PaymentService directly
        Task { @MainActor in
            for await _ in PaymentService.shared.$purchasedProductIDs.values {
                self.refreshLicenseStatus()
            }
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

        // Check for actual purchase via StoreKit
        if PaymentService.shared.isProUnlocked {
            updateStatus(.pro, remaining: 0)
            return
        }
        
        // Check trial status
        if let firstLaunch = defaults.object(forKey: firstLaunchKey) as? Date {
            let calendar = Calendar.current
            let now = Date()
            
            let components = calendar.dateComponents([.day], from: firstLaunch, to: now)
            let daysElapsed = components.day ?? 0
            
            if daysElapsed < trialDurationDays {
                updateStatus(.trial, remaining: trialDurationDays - daysElapsed)
            } else {
                updateStatus(.free, remaining: 0)
            }
        } else {
            // First launch - start trial
            let now = Date()
            defaults.set(now, forKey: firstLaunchKey)
            updateStatus(.trial, remaining: trialDurationDays)
        }
    }

    private func updateStatus(_ newStatus: LicenseStatus, remaining: Int) {
        let oldStatus = self.status
        self.status = newStatus
        self.trialDaysRemaining = remaining
        
        if oldStatus != newStatus || remaining != trialDaysRemaining {
            checkTrialThresholds(status: newStatus, remaining: remaining)
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("LicenseStatusChanged"),
            object: self
        )
    }

    private func checkTrialThresholds(status: LicenseStatus, remaining: Int) {
        guard status == .trial || status == .free else { return }
        
        let thresholds = [3, 1, 0]
        let currentThreshold = status == .free ? 0 : remaining
        
        guard thresholds.contains(currentThreshold) else { return }
        
        // Only notify once per threshold per day
        let lastNotified = defaults.integer(forKey: lastNotifiedThresholdKey)
        let lastDate = defaults.object(forKey: "MGLastNotifiedDate") as? Date ?? .distantPast
        
        if lastNotified == currentThreshold && Calendar.current.isDateInToday(lastDate) {
            return
        }
        
        sendExpirationNotification(daysRemaining: currentThreshold)
        
        defaults.set(currentThreshold, forKey: lastNotifiedThresholdKey)
        defaults.set(Date(), forKey: "MGLastNotifiedDate")
    }

    private func sendExpirationNotification(daysRemaining: Int) {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = "TRIAL_EXPIRATION"
        
        if daysRemaining > 0 {
            content.title = "MouseGestures Trial Ending"
            content.body = "Your Pro trial expires in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s"). Upgrade now to keep all features."
        } else {
            content.title = "MouseGestures Trial Expired"
            content.body = "Your Pro trial has expired. Upgrade to Pro to continue using advanced features."
        }
        
        content.userInfo = ["daysRemaining": daysRemaining]
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "com.mousegestures.trial.expiration",
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
        return status == .pro || status == .trial
    }
    
    /// Returns true if the app is currently in trial mode
    public var isTrial: Bool {
        return status == .trial
    }
    
    /// Purchase the Pro version (no longer simulated)
    public func purchasePro() {
        // This is now handled via PaymentService in the UI
        refreshLicenseStatus()
    }
    
    /// Reset the trial (for testing purposes)
    public func resetTrial() {
        defaults.removeObject(forKey: firstLaunchKey)
        refreshLicenseStatus()
        
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
