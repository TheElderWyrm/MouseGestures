import Cocoa

// MARK: - App Configuration Detector Plugin

/// Plugin that detects app switches and manages app-specific configurations
/// Implements ActivationProvider for the coordinator system
class AppConfigurationDetectorPlugin: BaseDetectionPlugin, ActivationProvider {

    // MARK: - Constants

    public static let pluginIdentifier = "com.mousegestures.detection.appconfig"

    // MARK: - Setting Keys

    enum SettingKeys {
        static let autoProfileSwitch = "autoProfileSwitch"
        static let hapticOnSwitch = "hapticOnSwitch"
        static let appHistorySize = "appHistorySize"
    }

    // MARK: - Properties

    override var identifier: String { Self.pluginIdentifier }
    override var name: String { "App Configuration Detector" }
    override var description: String { "Detects app switches and manages per-app gesture profiles" }
    override var priority: Int { 250 } // Very high priority - needs to run before other detectors

    // MARK: - Settings Definitions

    override var settingsDefinitions: [PluginSettingDefinition] {
        [
            PluginSettingDefinition(
                key: SettingKeys.autoProfileSwitch,
                displayName: "Auto-Switch Profiles",
                description: "Automatically switch to app-specific profiles when changing apps",
                category: .general,
                type: .toggle(label: "Enabled"),
                defaultValue: true,
                isAdvanced: false
            ),
            PluginSettingDefinition(
                key: SettingKeys.hapticOnSwitch,
                displayName: "Haptic Feedback on Switch",
                description: "Provide haptic feedback when profile auto-switches",
                category: .general,
                type: .toggle(label: "Enabled"),
                defaultValue: true,
                isAdvanced: false,
                dependsOn: .init(key: SettingKeys.autoProfileSwitch, condition: .isTrue)
            ),
            PluginSettingDefinition(
                key: SettingKeys.appHistorySize,
                displayName: "App History Size",
                description: "Number of recent apps to remember for quick configuration",
                category: .general,
                type: .stepper(min: 5, max: 25, step: 5),
                defaultValue: 10,
                isAdvanced: true
            )
        ]
    }

    // MARK: - Computed Settings

    private var autoProfileSwitchEnabled: Bool {
        settings.getBool(SettingKeys.autoProfileSwitch, default: true)
    }

    private var hapticOnSwitchEnabled: Bool {
        settings.getBool(SettingKeys.hapticOnSwitch, default: true)
    }

    private var maxAppHistoryFromSettings: Int {
        settings.getInt(SettingKeys.appHistorySize, default: 10)
    }

    // State tracking
    private var currentAppBundleId: String?
    private var currentAppName: String?
    private var appObserver: Any?

    // Recent app history for "Use Current App" feature
    private var recentAppHistory: [(bundleId: String, name: String)] = []

    // Statistics
    private var appSwitchCount = 0
    private var profileAutoSwitchCount = 0

    // MARK: - ActivationProvider Protocol

    var providedActivationTypes: [ActivationType] {
        return [.appChange]
    }

    func getActivationState(for type: ActivationType) -> ActivationState? {
        guard type == .appChange else { return nil }
        return ActivationState(
            type: .appChange,
            isEngaged: currentAppBundleId != nil,
            metadata: [
                "bundleId": currentAppBundleId ?? "none",
                "appName": currentAppName ?? "none",
                "isDisabled": isCurrentAppDisabled()
            ]
        )
    }

    func enableDetection(for type: ActivationType) {
        // App change detection is always active - nothing to enable
    }

    func disableDetection(for type: ActivationType) {
        // App change detection is always active - nothing to disable
    }

    func isDetectionActive(for type: ActivationType) -> Bool {
        return state == .running
    }

    // MARK: - Plugin-Declared Behavioral Properties

    func efficiencyScore(for type: ActivationType) -> Int {
        guard type == .appChange else { return 50 }
        return 70 // Event-based but has computation
    }

    func isAlwaysActive(for type: ActivationType) -> Bool {
        guard type == .appChange else { return false }
        return true
    }

    func isInfrastructure(for type: ActivationType) -> Bool {
        guard type == .appChange else { return false }
        return true // Provides system-level app tracking, always runs
    }

    // REMOVED: gestureUsesActivation - moved to ActivationMapper
    // Plugin no longer needs to understand gesture structure

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

    override func initialize(context: DetectionContext) throws {
        try super.initialize(context: context)

        // Register with ActivationCoordinator
        ActivationCoordinator.shared.registerProvider(self, for: providedActivationTypes)
    }

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

        // Notify coordinator of initial app (include isDisabled for cross-plugin queries)
        if let bundleId = currentAppBundleId {
            ActivationCoordinator.shared.activationEngaged(.appChange, metadata: [
                "bundleId": bundleId,
                "appName": currentAppName ?? "Unknown",
                "isDisabled": context?.configuration.isAppDisabled(bundleId: bundleId) ?? false
            ])
        }

        context?.logger.log("App configuration detection started - Current app: \(currentAppName ?? "Unknown")", file: #file, function: #function, line: #line)
    }

    override func stop() {
        // Notify coordinator that this plugin is stopping
        ActivationCoordinator.shared.pluginStopping(self)

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

    override func cleanup() {
        ActivationCoordinator.shared.unregisterProvider(self)
        super.cleanup()
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

            // Notify coordinator of app change (include isDisabled for cross-plugin queries)
            ActivationCoordinator.shared.activationEngaged(.appChange, metadata: [
                "bundleId": bundleId,
                "appName": newAppName,
                "previousApp": previousApp,
                "isDisabled": context?.configuration.isAppDisabled(bundleId: bundleId) ?? false
            ])

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

        // Limit size using setting
        let maxSize = maxAppHistoryFromSettings
        if recentAppHistory.count > maxSize {
            recentAppHistory = Array(recentAppHistory.prefix(maxSize))
        }
    }

    // MARK: - Profile Management

    private func checkForAppProfile(bundleId: String, appName: String) {
        // Check if auto-switching is enabled
        guard autoProfileSwitchEnabled else { return }
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
        // Check both global haptic setting and plugin-specific setting
        guard (context?.configuration.hapticFeedbackEnabled ?? false) && hapticOnSwitchEnabled else { return }

        DispatchQueue.main.async {
            // Haptic feedback
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    // MARK: - Configuration

    override func configurationChanged() {
        super.configurationChanged()

        // Re-check current app configuration
        if let bundleId = currentAppBundleId,
           let name = currentAppName {
            checkForAppProfile(bundleId: bundleId, appName: name)

            // Re-notify coordinator with updated isDisabled status
            // (user may have changed disabled apps in settings)
            ActivationCoordinator.shared.activationEngaged(.appChange, metadata: [
                "bundleId": bundleId,
                "appName": name,
                "isDisabled": context?.configuration.isAppDisabled(bundleId: bundleId) ?? false
            ])
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
