import Cocoa

// MARK: - App Configuration Detector Plugin

/// Plugin that detects app switches and manages app-specific configurations
class AppConfigurationDetectorPlugin: BaseDetectionPlugin {
    
    // MARK: - Constants
    
    public static let pluginIdentifier = "com.mousegestures.detection.appconfig"
    
    // MARK: - Properties
    
    override var identifier: String { Self.pluginIdentifier }
    override var name: String { "App Configuration Detector" }
    override var description: String { "Detects app switches and manages per-app gesture profiles" }
    override var priority: Int { 250 } // Very high priority - needs to run before other detectors
    
    // State tracking
    private var currentAppBundleId: String?
    private var currentAppName: String?
    private var appObserver: Any?
    
    // Recent app history for "Use Current App" feature
    private var recentAppHistory: [(bundleId: String, name: String)] = []
    private let maxAppHistory = 10
    
    // Statistics
    private var appSwitchCount = 0
    private var profileAutoSwitchCount = 0
    
    // MARK: - Public Interface
    
    /// Check if the current app has gestures disabled
    func isCurrentAppDisabled() -> Bool {
        guard let bundleId = currentAppBundleId else { return false }
        return context?.configuration.isAppDisabled(bundleId: bundleId) ?? false
    }
    
    /// Get the current app bundle ID
    var currentApp: (bundleId: String, name: String)? {
        guard let bundleId = currentAppBundleId,
              let name = currentAppName else { return nil }
        return (bundleId, name)
    }
    
    /// Get recent app history for UI
    var appHistory: [(bundleId: String, name: String)] {
        return recentAppHistory
    }
    
    // MARK: - Plugin Lifecycle
    
    override func start() throws {
        try super.start()
        
        // Get current app
        updateCurrentApp()
        
        // Monitor app switches
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppSwitch(notification)
        }
        
        context?.logger.log("App configuration detection started - Current app: \(currentAppName ?? "Unknown")", file: #file, function: #function, line: #line)
    }
    
    override func stop() {
        // Remove observer
        if let observer = appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appObserver = nil
        }
        
        // Reset state
        currentAppBundleId = nil
        currentAppName = nil
        
        super.stop()
    }
    
    // MARK: - App Detection
    
    private func updateCurrentApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        
        currentAppBundleId = app.bundleIdentifier
        currentAppName = app.localizedName ?? "Unknown"
        
        // Add to history if not already at the top
        if let bundleId = currentAppBundleId,
           let name = currentAppName {
            addToAppHistory(bundleId: bundleId, name: name)
        }
    }
    
    private func handleAppSwitch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        
        let newBundleId = app.bundleIdentifier
        let newAppName = app.localizedName ?? "Unknown"
        
        // Check if app actually changed
        guard newBundleId != currentAppBundleId else { return }
        
        let previousApp = currentAppName ?? "None"
        currentAppBundleId = newBundleId
        currentAppName = newAppName
        
        appSwitchCount += 1
        
        if let bundleId = newBundleId {
            addToAppHistory(bundleId: bundleId, name: newAppName)
            
            context?.logger.log("App switched: \(previousApp) → \(newAppName)", file: #file, function: #function, line: #line)
            
            // Check for app-specific profile
            checkForAppProfile(bundleId: bundleId, appName: newAppName)
            
            // Check if app is disabled
            if isCurrentAppDisabled() {
                context?.logger.log("Gestures disabled for app: \(newAppName)", file: #file, function: #function, line: #line)
            }
        }
    }
    
    private func addToAppHistory(bundleId: String, name: String) {
        // Remove if already exists
        recentAppHistory.removeAll { $0.bundleId == bundleId }
        
        // Add to front
        recentAppHistory.insert((bundleId, name), at: 0)
        
        // Limit size
        if recentAppHistory.count > maxAppHistory {
            recentAppHistory = Array(recentAppHistory.prefix(maxAppHistory))
        }
    }
    
    // MARK: - Profile Management
    
    private func checkForAppProfile(bundleId: String, appName: String) {
        guard let config = context?.configuration else { return }
        
        // Check if app has a specific profile mapping
        if let appConfig = config.getAppConfiguration(bundleId: bundleId),
           let profileId = appConfig.profileId,
           let profile = config.profiles.first(where: { $0.id == profileId }) {
            
            // Switch to app-specific profile
            profileAutoSwitchCount += 1
            context?.logger.log("Auto-switching to profile '\(profile.name)' for app '\(appName)'", file: #file, function: #function, line: #line)
            
            triggerProfileSwitch(profile)
            
            // Show visual feedback
            showProfileSwitchNotification(profile: profile, appName: appName)
        }
    }
    
    private func showProfileSwitchNotification(profile: ConfigurationProfile, appName: String) {
        guard context?.configuration.hapticFeedbackEnabled ?? false else { return }
        
        DispatchQueue.main.async {
            // Haptic feedback
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            
            // Visual notification could be added here
            // For now, just rely on logging
        }
    }
    
    // MARK: - Configuration
    
    override func configurationChanged() {
        super.configurationChanged()
        
        // Re-check current app configuration
        if let bundleId = currentAppBundleId,
           let name = currentAppName {
            checkForAppProfile(bundleId: bundleId, appName: name)
        }
    }
    
    // MARK: - Statistics
    
    override func getStatistics() -> DetectionPluginStatistics {
        return DetectionPluginStatistics(
            eventsDetected: appSwitchCount,
            gesturesTriggered: 0, // This plugin doesn't directly trigger gestures
            errorsEncountered: 0,
            timeSinceLastEvent: nil,
            cpuUsage: 0.1,
            memoryUsage: 0,
            customStats: [
                "currentApp": currentAppName ?? "None",
                "currentBundleId": currentAppBundleId ?? "None",
                "appDisabled": isCurrentAppDisabled(),
                "profileAutoSwitches": profileAutoSwitchCount,
                "appHistorySize": recentAppHistory.count
            ]
        )
    }
    
    // MARK: - Configuration View
    
    override func configurationView() -> NSView? {
        // Could provide UI for managing app configurations
        // For now, this is handled in the main preferences window
        return nil
    }
}

// MARK: - Static Access for Compatibility

extension AppConfigurationDetectorPlugin {
    /// Static accessor for recent app history (for backward compatibility)
    public static var recentAppHistory: [(bundleId: String, name: String)] {
        guard let plugin = DetectionPluginManager.shared.getPlugin(pluginIdentifier) as? AppConfigurationDetectorPlugin else {
            return []
        }
        return plugin.appHistory
    }
}
