import Foundation
import Cocoa

// MARK: - Detection Plugin Manager

/// Manages all detection plugins and coordinates their operation
class DetectionPluginManager: NSObject {
    
    // MARK: - Singleton
    
    static let shared = DetectionPluginManager()
    
    // MARK: - Properties
    
    private var plugins: [String: DetectionPlugin] = [:]
    private var pluginOrder: [String] = [] // Ordered by priority
    private var isRunning = false
    
    var isEnabled: Bool {
        return isRunning
    }
    
    // Detection delegate (forwards to ActionExecutionManager)
    weak var delegate: DetectionManagerDelegate?
    
    // Configuration access adapter
    private let configurationAccess: ConfigurationAccessAdapter
    
    // Plugin storage directory
    private let storageDirectory: URL
    
    // Statistics
    private var startTime: Date?
    
    // MARK: - Initialization
    
    private override init() {
        // Set up storage directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.storageDirectory = appSupport
            .appendingPathComponent("MouseGestures", isDirectory: true)
            .appendingPathComponent("DetectionPlugins", isDirectory: true)
        
        // Create configuration adapter
        self.configurationAccess = ConfigurationAccessAdapter()
        
        super.init()
        
        // Create storage directory if needed
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        
        // Load built-in plugins
        loadBuiltInPlugins()

        // Discover and load external detection plugins
        discoverExternalPlugins()

        // Listen for configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configurationChanged),
            name: NSNotification.Name("GestureConfigurationChanged"),
            object: nil
        )
    }
    
    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Plugin Loading
    
    private func loadBuiltInPlugins() {
        // Load all built-in detection plugins
        let builtInPlugins: [DetectionPlugin] = [
            ModifierKeyDetectorPlugin(),
            ScreenZoneDetectorPlugin(),
            KeyboardShortcutDetectorPlugin(),
            MouseButtonDetectorPlugin(),
            AppConfigurationDetectorPlugin(),
            TestDetectionPlugin()
        ]
        
        for plugin in builtInPlugins {
            registerPlugin(plugin)
        }
        
        // Load saved settings for all plugins
        loadAllPluginSettings()

        log.log("Loaded \(plugins.count) built-in detection plugins")
    }

    /// Scan the user DetectionPlugins directory for external .plugin/.bundle files
    private func discoverExternalPlugins() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let pluginDir = appSupport
            .appendingPathComponent("MouseGestures", isDirectory: true)
            .appendingPathComponent("DetectionPlugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: pluginDir, includingPropertiesForKeys: nil) else { return }
        for item in contents where item.pathExtension == "plugin" || item.pathExtension == "bundle" {
            loadExternalPlugin(at: item)
        }
    }

    private func loadExternalPlugin(at url: URL) {
        guard let bundle = Bundle(url: url), bundle.load() else {
            log.log("DetectionPluginManager: failed to load bundle at \(url.lastPathComponent)")
            return
        }
        guard let cls = bundle.principalClass as? NSObject.Type,
              let plugin = cls.init() as? DetectionPlugin else {
            log.log("DetectionPluginManager: principal class in \(url.lastPathComponent) does not conform to DetectionPlugin")
            bundle.unload()
            return
        }
        registerPlugin(plugin)
        log.log("DetectionPluginManager: loaded external plugin \(plugin.name) v\(plugin.version)")
    }
    
    /// Register a detection plugin
    func registerPlugin(_ plugin: DetectionPlugin) {
        let identifier = plugin.identifier
        
        // Create plugin context
        let logger = PrefixedLogger(prefix: "[DetectionPlugin:\(identifier)]")
        let pluginStorage = storageDirectory.appendingPathComponent(identifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: pluginStorage, withIntermediateDirectories: true)
        
        let context = DetectionContext(
            delegate: self,
            logger: logger,
            configuration: configurationAccess,
            pluginManager: self,
            storageDirectory: pluginStorage
        )
        
        // Initialize the plugin
        do {
            try plugin.initialize(context: context)
            plugins[identifier] = plugin
            updatePluginOrder()
            log.log("Registered detection plugin: \(plugin.name) v\(plugin.version)")
        } catch {
            log.log("Failed to initialize detection plugin \(plugin.name): \(error)")
        }
    }
    
    /// Unregister a detection plugin
    func unregisterPlugin(identifier: String) {
        guard let plugin = plugins[identifier] else { return }
        
        // Stop if running
        if isRunning {
            plugin.stop()
        }
        
        // Clean up
        plugin.cleanup()
        
        // Remove from registry
        plugins.removeValue(forKey: identifier)
        updatePluginOrder()
        
        log.log("Unregistered detection plugin: \(plugin.name)")
    }
    
    // MARK: - Plugin Control
    
    /// Start all enabled detection plugins
    func start() {
        guard !isRunning else { return }
        
        // Check for accessibility permissions
        guard AccessibilityPermissionManager.hasPermission() else {
            log.log("Cannot start detection plugins: Accessibility permissions not granted")
            NotificationCenter.default.post(name: NSNotification.Name("AccessibilityPermissionNeeded"), object: nil)
            return
        }
        
        isRunning = true
        startTime = Date()
        
        // Start plugins in priority order
        for identifier in pluginOrder {
            guard let plugin = plugins[identifier], plugin.isEnabled else { continue }
            
            do {
                try plugin.start()
            } catch {
                log.log("Failed to start plugin \(plugin.name): \(error)")
            }
        }
        
        // Initialize activation coordinator dependencies after plugins are started
        ActivationCoordinator.shared.rebuildDependencies()
        
        // Start zone highlighting if enabled
        ZoneHighlightManager.shared.startHighlighting()
        
        log.log("Detection plugin system started with \(getActivePluginCount()) active plugins")
    }
    
    /// Stop all detection plugins
    func stop() {
        guard isRunning else { return }
        
        isRunning = false
        
        // Stop plugins in reverse priority order
        for identifier in pluginOrder.reversed() {
            guard let plugin = plugins[identifier] else { continue }
            plugin.stop()
        }
        
        // Stop zone highlighting
        ZoneHighlightManager.shared.stopHighlighting()
        
        log.log("Detection plugin system stopped")
    }
    
    /// Enable/disable a specific plugin
    func setPluginEnabled(_ identifier: String, enabled: Bool) {
        guard let plugin = plugins[identifier] else { return }
        
        plugin.isEnabled = enabled
        
        if isRunning {
            if enabled {
                do {
                    try plugin.start()
                    // Rebuild dependencies when plugin is enabled
                    ActivationCoordinator.shared.rebuildDependencies()
                    log.log("Started plugin: \(plugin.name)")
                } catch {
                    log.log("Failed to start plugin \(plugin.name): \(error)")
                }
            } else {
                plugin.stop()
                // Rebuild dependencies when plugin is disabled
                ActivationCoordinator.shared.rebuildDependencies()
                log.log("Stopped plugin: \(plugin.name)")
            }
        }
    }
    
    // MARK: - Plugin Query
    
    /// Get all registered plugins
    func getAllPlugins() -> [DetectionPlugin] {
        return pluginOrder.compactMap { plugins[$0] }
    }
    
    /// Get a specific plugin
    func getPlugin(_ identifier: String) -> DetectionPlugin? {
        return plugins[identifier]
    }
    
    /// Get active plugin count
    func getActivePluginCount() -> Int {
        return plugins.values.filter { $0.isEnabled }.count
    }
    
    /// Get plugin statistics
    func getPluginStatistics(_ identifier: String) -> DetectionPluginStatistics? {
        return plugins[identifier]?.getStatistics()
    }
    
    /// Get overall statistics
    func getOverallStatistics() -> DetectionSystemStatistics {
        var totalEvents = 0
        var totalGestures = 0
        var totalErrors = 0
        var pluginStats: [String: DetectionPluginStatistics] = [:]
        
        for (identifier, plugin) in plugins {
            let stats = plugin.getStatistics()
            totalEvents += stats.eventsDetected
            totalGestures += stats.gesturesTriggered
            totalErrors += stats.errorsEncountered
            pluginStats[identifier] = stats
        }
        
        let uptime = startTime.map { Date().timeIntervalSince($0) } ?? 0
        
        return DetectionSystemStatistics(
            totalEventsDetected: totalEvents,
            totalGesturesTriggered: totalGestures,
            totalErrorsEncountered: totalErrors,
            activePlugins: getActivePluginCount(),
            totalPlugins: plugins.count,
            uptime: uptime,
            pluginStatistics: pluginStats
        )
    }
    
    // MARK: - Configuration
    
    @objc private func configurationChanged() {
        log.log("Detection plugins received configuration change")
        
        // Notify all plugins of configuration change
        for plugin in plugins.values {
            plugin.configurationChanged()
        }
        
        // Coordinator also listens for this, but ensure dependencies are rebuilt
        ActivationCoordinator.shared.rebuildDependencies()
    }
    
    // MARK: - Settings Management
    
    /// Get all settings definitions from all plugins, grouped by category
    func getAllSettingsDefinitions() -> [PluginSettingDefinition.SettingCategory: [(plugin: DetectionPlugin, definition: PluginSettingDefinition)]] {
        var grouped: [PluginSettingDefinition.SettingCategory: [(plugin: DetectionPlugin, definition: PluginSettingDefinition)]] = [:]
        
        for plugin in getAllPlugins() {
            for definition in plugin.settingsDefinitions {
                if grouped[definition.category] == nil {
                    grouped[definition.category] = []
                }
                grouped[definition.category]?.append((plugin: plugin, definition: definition))
            }
        }
        
        return grouped
    }
    
    /// Get settings definitions for a specific plugin
    func getSettingsDefinitions(for pluginId: String) -> [PluginSettingDefinition] {
        return plugins[pluginId]?.settingsDefinitions ?? []
    }
    
    /// Load settings for all plugins from Configuration
    func loadAllPluginSettings() {
        for (identifier, plugin) in plugins {
            loadPluginSettings(plugin, identifier: identifier)
        }
    }
    
    /// Load settings for a specific plugin
    private func loadPluginSettings(_ plugin: DetectionPlugin, identifier: String) {
        let savedSettings = Configuration.shared.getPluginSettings(identifier)
        if !savedSettings.isEmpty {
            plugin.settings.load(from: savedSettings)
            log.log("Loaded \(savedSettings.count) settings for plugin: \(plugin.name)")
        }
    }
    
    /// Save settings for all plugins to Configuration
    func saveAllPluginSettings() {
        for (identifier, plugin) in plugins {
            savePluginSettings(plugin, identifier: identifier)
        }
    }
    
    /// Save settings for a specific plugin
    func savePluginSettings(_ plugin: DetectionPlugin, identifier: String) {
        let settingsDict = plugin.settings.toDictionary()
        Configuration.shared.setPluginSettings(identifier, settings: settingsDict)
    }
    
    /// Update a single setting for a plugin
    func updatePluginSetting(_ pluginId: String, key: String, value: Any) {
        guard let plugin = plugins[pluginId] else {
            log.log("Cannot update setting: plugin \(pluginId) not found")
            return
        }
        
        // Validate the setting
        let (isValid, errorMessage) = plugin.settings.validate(key, value: value)
        if !isValid {
            log.log("Setting validation failed for \(key): \(errorMessage ?? "unknown error")")
            return
        }
        
        // Update the setting
        plugin.settings.set(key, value: value)
        
        // Persist to Configuration
        savePluginSettings(plugin, identifier: pluginId)
        
        log.log("Updated setting \(key) for plugin \(plugin.name)")
    }
    
    /// Reset all settings for a plugin to defaults
    func resetPluginSettings(_ pluginId: String) {
        guard let plugin = plugins[pluginId] else { return }
        
        plugin.settings.resetToDefaults()
        savePluginSettings(plugin, identifier: pluginId)
        
        log.log("Reset all settings for plugin: \(plugin.name)")
    }
    
    // MARK: - Cross-Plugin Queries (Coordinator-Based)
    
    /// Check if the current app is disabled.
    /// Queries via ActivationCoordinator metadata rather than casting to a specific plugin type.
    func isCurrentAppDisabled() -> Bool {
        let appState = ActivationCoordinator.shared.getState(for: .appChange)
        return appState.metadata["isDisabled"] as? Bool ?? false
    }
    
// MARK: - Helpers
    
    private func updatePluginOrder() {
        pluginOrder = plugins.keys.sorted { id1, id2 in
            let priority1 = plugins[id1]?.priority ?? 0
            let priority2 = plugins[id2]?.priority ?? 0
            return priority1 > priority2
        }
    }
}

// MARK: - DetectionPluginDelegate Implementation

extension DetectionPluginManager: DetectionPluginDelegate {
    
    func detectionPlugin(_ plugin: DetectionPlugin, didDetectGesture gesture: Gesture, context: GestureContext) {
        // Check if app is disabled (except for AppConfigurationDetectorPlugin itself)
        if plugin.identifier != AppConfigurationDetectorPlugin.pluginIdentifier && isCurrentAppDisabled() {
            return
        }
        
        // Forward to delegate based on context
        switch context.source {
        case .screenZone(let zone, let dragState):
            delegate?.detectionManager(self, executeGesture: gesture, fromZone: zone, withDragState: dragState, modifiers: context.modifiers)
            
        case .keyboard(let trigger):
            delegate?.detectionManager(self, executeKeyboardTriggeredGesture: gesture, trigger: trigger)
            
        case .mouseButton(let button, let modifiers):
            delegate?.detectionManager(self, executeMouseButtonTriggeredGesture: gesture, button: button, modifiers: modifiers)
            
        case .`repeat`:
            delegate?.detectionManager(self, executeRepeatedGesture: gesture)
            
        case .custom(let description):
            log.log("Custom gesture trigger: \(description)")
            delegate?.detectionManager(self, executeRepeatedGesture: gesture)
        }
    }
    
    func detectionPlugin(_ plugin: DetectionPlugin, didTriggerProfileSwitch profile: ConfigurationProfile) {
        delegate?.detectionManager(self, executeProfileSwitch: profile)
    }
    
    func detectionPlugin(_ plugin: DetectionPlugin, stateChanged state: DetectionPluginState) {
        log.log("Plugin \(plugin.name) state changed to: \(state)")
    }
    
    func detectionPlugin(_ plugin: DetectionPlugin, didEncounterError error: Error) {
        log.log("Error in plugin \(plugin.name): \(error)")
    }
    
    func detectionPluginShouldContinue(_ plugin: DetectionPlugin) -> Bool {
        return isRunning && plugin.isEnabled
    }
}

// MARK: - Detection Plugin Logger
// Now uses the shared PrefixedLogger from Extensions.swift
typealias DetectionPluginLogger = PrefixedLogger

// MARK: - Configuration Access Adapter

/// Adapter to provide configuration access to plugins
class ConfigurationAccessAdapter: ConfigurationAccess {
    
    var gestures: [Gesture] {
        return Configuration.shared.gestures
    }
    
    var profiles: [ConfigurationProfile] {
        return Configuration.shared.profiles
    }
    
    var activeProfileId: String? {
        return Configuration.shared.activeProfileId?.uuidString
    }
    
    var edgeThreshold: CGFloat {
        return Configuration.shared.edgeThreshold
    }
    
    var cornerSize: CGFloat {
        return Configuration.shared.cornerSize
    }
    
    var cornerBuffer: CGFloat {
        return Configuration.shared.cornerBuffer
    }
    
    var hapticFeedbackEnabled: Bool {
        return Configuration.shared.hapticFeedbackEnabled
    }
    
    var isEnabled: Bool {
        return Configuration.shared.isEnabled
    }
    
    func getAppConfiguration(bundleId: String) -> AppConfiguration? {
        // Check if app is disabled
        let disabledApp = Configuration.shared.disabledApps.first { $0.appBundleIdentifier == bundleId }
        if disabledApp != nil {
            return AppConfiguration(appName: disabledApp!.appName,
                                  bundleId: bundleId,
                                  profileId: nil,
                                  isDisabled: true)
        }
        
        // Check for profile mapping
        let mapping = Configuration.shared.appProfileMappings.first { $0.appBundleIdentifier == bundleId }
        if let mapping = mapping {
            return AppConfiguration(appName: mapping.appName,
                                  bundleId: bundleId,
                                  profileId: mapping.profileId,
                                  isDisabled: false)
        }
        
        return nil
    }
    
    func isAppDisabled(bundleId: String) -> Bool {
        return Configuration.shared.disabledApps.contains { $0.appBundleIdentifier == bundleId }
    }
}

// MARK: - Detection System Statistics

/// Overall statistics for the detection system
struct DetectionSystemStatistics {
    let totalEventsDetected: Int
    let totalGesturesTriggered: Int
    let totalErrorsEncountered: Int
    let activePlugins: Int
    let totalPlugins: Int
    let uptime: TimeInterval
    let pluginStatistics: [String: DetectionPluginStatistics]
}

/// Protocol for handling gesture execution requests from DetectionManager
protocol DetectionManagerDelegate: AnyObject {
    func detectionManager(_ manager: Any, executeGesture gesture: Gesture, fromZone zone: ScreenZone, withDragState dragState: DragModifier, modifiers: NSEvent.ModifierFlags)
    func detectionManager(_ manager: Any, executeRepeatedGesture gesture: Gesture)
    func detectionManager(_ manager: Any, executeKeyboardTriggeredGesture gesture: Gesture, trigger: KeyboardTrigger)
    func detectionManager(_ manager: Any, executeMouseButtonTriggeredGesture gesture: Gesture, button: MouseButtonTrigger.MouseButton, modifiers: NSEvent.ModifierFlags)
    func detectionManager(_ manager: Any, executeProfileSwitch profile: ConfigurationProfile)
}
