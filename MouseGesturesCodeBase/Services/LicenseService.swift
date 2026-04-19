import Foundation
import Cocoa

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
            status = .free
            return
        }

        // Check for actual purchase via StoreKit
        if PaymentService.shared.isProUnlocked {
            status = .pro
            return
        }
        
        // Check trial status
        if let firstLaunch = defaults.object(forKey: firstLaunchKey) as? Date {
            let calendar = Calendar.current
            let now = Date()
            
            let components = calendar.dateComponents([.day], from: firstLaunch, to: now)
            let daysElapsed = components.day ?? 0
            
            if daysElapsed < trialDurationDays {
                status = .trial
                trialDaysRemaining = trialDurationDays - daysElapsed
            } else {
                status = .free
                trialDaysRemaining = 0
            }
        } else {
            // First launch - start trial
            let now = Date()
            defaults.set(now, forKey: firstLaunchKey)
            status = .trial
            trialDaysRemaining = trialDurationDays
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
