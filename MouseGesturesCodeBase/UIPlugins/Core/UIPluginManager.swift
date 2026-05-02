import SwiftUI
import Combine

// MARK: - UI Plugin Manager

/// Manages all UI tab plugins in the application
class UIPluginManager: ObservableObject {
    static let shared = UIPluginManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var loadedPlugins: [String: any UIPlugin] = [:]
    @Published private(set) var visiblePlugins: [any UIPlugin] = []
    @Published private(set) var pluginStates: [String: UIPluginState] = [:]
    @Published private(set) var isLoading = false
    
    // MARK: - Private Properties
    
    private let context: UIPluginContextImpl
    private var cancellables = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "com.mousegestures.uipluginmanager", attributes: .concurrent)
    private var pluginObservers: [String: NSObjectProtocol] = [:]
    
    // MARK: - Initialization
    
    private init() {
        self.context = UIPluginContextImpl()
        setupNotifications()
        loadBuiltInPlugins()
    }
    
    // MARK: - Setup
    
    private func setupNotifications() {
        // Listen for developer mode changes
        NotificationCenter.default.publisher(for: Notification.Name("developerModeChanged"))
            .sink { [weak self] _ in
                self?.updateVisiblePlugins()
            }
            .store(in: &cancellables)
        
        // Listen for configuration changes
        NotificationCenter.default.publisher(for: Notification.Name("configurationDidChange"))
            .sink { [weak self] _ in
                self?.updateVisiblePlugins()
            }
            .store(in: &cancellables)
            
        // Listen for license status changes
        NotificationCenter.default.publisher(for: NSNotification.Name("LicenseStatusChanged"))
            .sink { [weak self] _ in
                self?.updateVisiblePlugins()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Plugin Loading
    
    /// Load all built-in plugins
    private func loadBuiltInPlugins() {
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            // Register built-in plugins
            let builtInPlugins: [any UIPlugin] = [
                GesturesUIPlugin(),
                SavedActionsUIPlugin(),
                ProfilesUIPlugin(),
                AppProfilesUIPlugin(),
                SettingsUIPlugin(),
                DeveloperUIPlugin()
            ]
            
            for plugin in builtInPlugins {
                await loadPlugin(plugin)
            }
            
            // Load custom plugins from directory
            await loadCustomPlugins()
            
            await MainActor.run {
                self.isLoading = false
                self.updateVisiblePlugins()
            }
        }
    }
    
    /// Load a single plugin
    private func loadPlugin(_ plugin: any UIPlugin) async {
        let identifier = plugin.identifier
        
        await MainActor.run {
            self.pluginStates[identifier] = .loading
        }
        
        do {
            // Initialize the plugin
            try await plugin.initialize(context: context)
            
            await MainActor.run {
                self.loadedPlugins[identifier] = plugin
                self.pluginStates[identifier] = .loaded
            }
            
            Logger.shared.log("Loaded UI plugin: \(identifier) v\(plugin.version)")
            
        } catch {
            await MainActor.run {
                self.pluginStates[identifier] = .error(error.localizedDescription)
            }
            Logger.shared.error("Failed to load UI plugin \(identifier): \(error)")
        }
    }
    
    /// Load custom plugins from the plugins directory
    private func loadCustomPlugins() async {
        // Get custom plugins directory
        let customPluginsPath = Configuration.applicationSupportDirectory
            .appendingPathComponent("UIPlugins")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: customPluginsPath, withIntermediateDirectories: true)
        
        do {
            let pluginFiles = try FileManager.default.contentsOfDirectory(
                at: customPluginsPath,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            for pluginFile in pluginFiles where pluginFile.pathExtension == "uiplugin" {
                Logger.shared.log("UIPluginManager: Loading external plugin at \(pluginFile.path)")
                
                guard let bundle = Bundle(url: pluginFile) else {
                    Logger.shared.error("UIPluginManager: Failed to create bundle for plugin at: \(pluginFile.path)")
                    continue
                }
                
                // Load the bundle
                guard bundle.load() else {
                    Logger.shared.error("UIPluginManager: Failed to load bundle for plugin at: \(pluginFile.path)")
                    continue
                }
                
                // Get the principal class, which must be an NSObject subclass
                guard let principalClass = bundle.principalClass as? NSObject.Type else {
                    Logger.shared.error("UIPluginManager: No principal class found in plugin at: \(pluginFile.path)")
                    bundle.unload()
                    continue
                }
                
                // Instantiate the class and check if the instance conforms to our protocol
                // Note: UIPlugin is a protocol, we need to cast to it.
                // We use any UIPlugin since it's a protocol with associated types or just a protocol.
                guard let plugin = principalClass.init() as? any UIPlugin else {
                    Logger.shared.error("UIPluginManager: Principal class '\(principalClass)' does not conform to UIPlugin protocol.")
                    bundle.unload()
                    continue
                }
                
                await loadPlugin(plugin)
                Logger.shared.log("UIPluginManager: Successfully loaded external plugin: \(plugin.identifier)")
            }
        } catch {
            Logger.shared.error("UIPluginManager: Error loading custom plugins: \(error)")
        }
        
        Logger.shared.log("Finished checking for custom UI plugins.")
    }
    
    // MARK: - Plugin Management
    
    /// Register a new plugin
    public func registerPlugin(_ plugin: any UIPlugin) async {
        await loadPlugin(plugin)
        updateVisiblePlugins()
    }
    
    /// Unload a plugin
    public func unloadPlugin(identifier: String) {
        guard let plugin = loadedPlugins[identifier] else { return }
        
        // Clean up the plugin
        plugin.cleanup()
        
        // Remove from loaded plugins
        loadedPlugins.removeValue(forKey: identifier)
        pluginStates[identifier] = .unloaded
        
        // Remove any observers
        if let observer = pluginObservers[identifier] {
            NotificationCenter.default.removeObserver(observer)
            pluginObservers.removeValue(forKey: identifier)
        }
        
        updateVisiblePlugins()
        
        Logger.shared.log("Unloaded UI plugin: \(identifier)")
    }
    
    /// Enable a plugin
    public func enablePlugin(identifier: String) {
        if loadedPlugins[identifier] != nil {
            pluginStates[identifier] = .loaded
            updateVisiblePlugins()
        }
    }
    
    /// Disable a plugin
    public func disablePlugin(identifier: String) {
        pluginStates[identifier] = .disabled
        updateVisiblePlugins()
    }
    
    /// Set the enabled state of a plugin
    public func setPluginEnabled(identifier: String, enabled: Bool) {
        if enabled {
            enablePlugin(identifier: identifier)
        } else {
            disablePlugin(identifier: identifier)
        }
    }
    
    /// Reload a plugin
    public func reloadPlugin(identifier: String) async {
        if let plugin = loadedPlugins[identifier] {
            unloadPlugin(identifier: identifier)
            await loadPlugin(plugin)
            updateVisiblePlugins()
        }
    }
    
    // MARK: - Visibility Management
    
    /// Update the list of visible plugins based on current conditions
    private func updateVisiblePlugins() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.visiblePlugins = self.loadedPlugins.values
                .filter { plugin in
                    // Check if plugin is enabled
                    guard self.pluginStates[plugin.identifier] != .disabled else { return false }
                    
                    // Check if plugin is Pro and user is not Pro (New requirement: remove tabs)
                    if plugin.isPro && !self.context.isPro { return false }
                    
                    // Check if plugin should be visible
                    return plugin.shouldBeVisible(context: self.context)
                }
                .sorted { $0.sortOrder < $1.sortOrder }
        }
    }
    
    /// Get all loaded plugins
    public func getAllPlugins() -> [any UIPlugin] {
        return Array(loadedPlugins.values).sorted { $0.sortOrder < $1.sortOrder }
    }
    
    /// Get a plugin by identifier
    public func getPlugin(identifier: String) -> (any UIPlugin)? {
        return loadedPlugins[identifier]
    }
    
    /// Get all plugins of a specific category
    public func getPlugins(category: UIPluginCategory) -> [any UIPlugin] {
        return loadedPlugins.values.filter { $0.category == category }
    }
    
    /// Check if a plugin is loaded
    public func isPluginLoaded(identifier: String) -> Bool {
        return loadedPlugins[identifier] != nil
    }
    
    /// Check if any plugins have been loaded
    public var hasLoadedPlugins: Bool {
        return !loadedPlugins.isEmpty
    }
    
    /// Check if a plugin is enabled
    public func isPluginEnabled(identifier: String) -> Bool {
        return pluginStates[identifier] != .disabled
    }
    
    /// Get the state of a plugin
    public func getPluginState(identifier: String) -> UIPluginState {
        return pluginStates[identifier] ?? .unloaded
    }
    
    // MARK: - Helper Methods
    
    /// Activate a plugin (called when its tab becomes active)
    @MainActor
    public func activatePlugin(identifier: String) {
        guard let plugin = loadedPlugins[identifier] else { return }
        
        // Update state
        pluginStates[identifier] = .active
        
        // Notify plugin
        plugin.onActivate()
    }
    
    /// Deactivate a plugin (called when its tab becomes inactive)
    @MainActor
    public func deactivatePlugin(identifier: String) {
        guard let plugin = loadedPlugins[identifier] else { return }
        
        // Update state
        if pluginStates[identifier] == .active {
            pluginStates[identifier] = .loaded
        }
        
        // Notify plugin
        plugin.onDeactivate()
    }
}

// MARK: - UI Plugin Context Implementation

class UIPluginContextImpl: UIPluginContext {
    var uiServices: UIServices { UIServices.shared }
    var configuration: Configuration { Configuration.shared }
    var profileManager: ProfileManager { ProfileManager.shared }
    var pluginManager: PluginManager { PluginManager.shared }
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var isDeveloperModeEnabled: Bool {
        uiServices.isDeveloperModeEnabled()
    }
    
    var isPro: Bool {
        uiServices.licenseService.isPro
    }
    
    func logger(_ message: String, level: LogLevel) {
        switch level {
        case .verbose:
            Logger.shared.verbose(message)
        case .debug:
            Logger.shared.debug(message)
        case .info:
            Logger.shared.log(message)
        case .warning:
            Logger.shared.warning(message)
        case .error:
            Logger.shared.error(message)
        }
    }
    
    @MainActor
    func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
    
    func getPreference(key: String) -> Any? {
        return UserDefaults.standard.object(forKey: key)
    }
    
    func setPreference(key: String, value: Any?) {
        if let value = value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    func postNotification(name: Notification.Name, object: Any?, userInfo: [AnyHashable: Any]?) {
        NotificationCenter.default.post(name: name, object: object, userInfo: userInfo)
    }
    
    func observeNotification(name: Notification.Name, using block: @escaping (Notification) -> Void) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: block)
    }
    
    func isFeatureEnabled(_ feature: String) -> Bool {
        // Check feature flags
        switch feature {
        case "gestures":
            return configuration.isEnabled
        case "developer":
            return isDeveloperModeEnabled
        default:
            return true
        }
    }
}

// MARK: - UI Plugin Error

enum UIPluginError: LocalizedError {
    case initializationFailed(String)
    case missingDependency(String)
    case invalidMetadata
    case loadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            return "Plugin initialization failed: \(message)"
        case .missingDependency(let dependency):
            return "Missing required dependency: \(dependency)"
        case .invalidMetadata:
            return "Invalid plugin metadata"
        case .loadFailed(let message):
            return "Failed to load plugin: \(message)"
        }
    }
}
