import Foundation
import SwiftUI

// MARK: - Service Plugin Manager
/// Manages all service plugins in the application
public class ServicePluginManager: ObservableObject {
    
    // MARK: - Singleton
    public static let shared = ServicePluginManager()
    
    // MARK: - Properties
    @Published private var loadedPlugins: [String: ServicePlugin] = [:]
    @Published private var serviceInstances: [String: Any] = [:]
    @Published public var isLoading: Bool = false
    
    private let pluginDirectory: URL
    private let externalPluginDirectory: URL
    private var fileWatcher: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.mousegestures.servicepluginmanager", attributes: .concurrent)
    
    // MARK: - Initialization
    private init() {
        // Setup plugin directories
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let mouseGesturesDir = appSupport.appendingPathComponent("MouseGestures", isDirectory: true)
        
        self.pluginDirectory = mouseGesturesDir
        self.externalPluginDirectory = mouseGesturesDir.appendingPathComponent("ServicePlugins", isDirectory: true)
        
        // Create directories if they don't exist
        try? FileManager.default.createDirectory(at: mouseGesturesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: externalPluginDirectory, withIntermediateDirectories: true)
        
        // Load all plugins
        loadBuiltInPlugins()
        loadExternalPlugins()
        setupFileWatcher()
    }
    
    deinit {
        fileWatcher?.cancel()
    }
    
    // MARK: - Plugin Loading
    
    /// Load all built-in service plugins
    private func loadBuiltInPlugins() {
        log.log("ServicePluginManager: Loading built-in plugins")
        
        // Register all built-in service plugins
        // Plugins with custom logic remain as classes; simple wrappers use factories.
        let builtInPlugins: [ServicePlugin] = [
            // Custom-logic plugins (have SettingsProvider, config options, or custom cleanup)
            AccessibilityPermissionServicePlugin(),
            LaunchAtLoginServicePlugin(),
            HapticFeedbackServicePlugin(),
            MenuBarVisibilityServicePlugin(),
            ZoneVisualizationServicePlugin(),
            DebugLoggingServicePlugin(),
            PerformanceMonitorServicePlugin(),
            // Simple singleton wrappers via factory
            GestureServicePluginFactory.gestureConfiguration(),
            GestureServicePluginFactory.profileManagement(),
            GestureServicePluginFactory.profileImportExport(),
            GestureServicePluginFactory.gestureSearch(),
            GestureServicePluginFactory.savedActionsSort(),
            DeveloperServicePluginFactory.logFile(),
            DeveloperServicePluginFactory.applicationReset(),
            DeveloperServicePluginFactory.settingsImportExport(),
            DeveloperServicePluginFactory.systemInformation(),
            DeveloperServicePluginFactory.applicationDiscovery(),
            DeveloperServicePluginFactory.debugReport(),
            DeveloperServicePluginFactory.developerModeToggle(),
            DeveloperServicePluginFactory.pluginManagement(),
            DeveloperServicePluginFactory.windowTargeting()
        ]
        
        for plugin in builtInPlugins {
            registerPlugin(plugin)
        }
        
        log.log("ServicePluginManager: Loaded \(builtInPlugins.count) built-in plugins")
    }
    
    /// Load external service plugins from the plugins directory
    private func loadExternalPlugins() {
        log.log("ServicePluginManager: Loading external plugins from \(externalPluginDirectory.path)")
        
        guard FileManager.default.fileExists(atPath: externalPluginDirectory.path) else {
            log.log("ServicePluginManager: External plugin directory does not exist")
            return
        }
        
        do {
            let pluginFiles = try FileManager.default.contentsOfDirectory(
                at: externalPluginDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            for pluginFile in pluginFiles where pluginFile.pathExtension == "serviceplugin" {
                loadExternalPlugin(at: pluginFile)
            }
            
            log.log("ServicePluginManager: Loaded \(pluginFiles.count) external plugins")
        } catch {
            log.log("ServicePluginManager: Error loading external plugins: \(error)")
        }
    }
    
    /// Load a single external plugin
    private func loadExternalPlugin(at url: URL) {
        log.log("ServicePluginManager: Loading external plugin at \(url.path)")
        
        guard let bundle = Bundle(url: url) else {
            log.log("ServicePluginManager: Failed to create bundle for plugin at: \(url.path)")
            return
        }
        
        // Load the bundle
        guard bundle.load() else {
            log.log("ServicePluginManager: Failed to load bundle for plugin at: \(url.path)")
            return
        }
        
        // Get the principal class, which must be an NSObject subclass
        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            log.log("ServicePluginManager: No principal class found in plugin at: \(url.path)")
            bundle.unload()
            return
        }
        
        // Instantiate the class and check if the instance conforms to our protocol
        guard let plugin = principalClass.init() as? ServicePlugin else {
            log.log("ServicePluginManager: Principal class '\(principalClass)' does not conform to ServicePlugin protocol or failed to instantiate.")
            bundle.unload()
            return
        }
        
        // Mark as external
        // (Assuming ServicePlugin has a way to mark as external if needed, 
        // but registerPlugin handles initialization and storage)
        
        registerPlugin(plugin)
        log.log("ServicePluginManager: Successfully loaded external plugin: \(plugin.identifier)")
    }
    
    /// Register a service plugin
    private func registerPlugin(_ plugin: ServicePlugin) {
        do {
            // Validate environment
            let validation = plugin.validateEnvironment()
            if !validation.isValid {
                log.log("ServicePluginManager: Plugin \(plugin.identifier) validation failed: \(validation.errors.joined(separator: ", "))")
                return
            }
            
            // Log warnings if any
            for warning in validation.warnings {
                log.log("ServicePluginManager: Plugin \(plugin.identifier) warning: \(warning)")
            }
            
            // Load any saved configuration for the plugin
            if let savedConfig = plugin.loadConfiguration() {
                plugin.applyConfiguration(savedConfig)
                log.log("ServicePluginManager: Loaded saved configuration for plugin \(plugin.identifier)")
            }
            
            // Initialize the plugin
            try plugin.initialize()
            
            // Store the plugin
            queue.async(flags: .barrier) {
                self.loadedPlugins[plugin.identifier] = plugin
                
                // Get and store the service instance if available
                if let instance = plugin.getServiceInstance() {
                    self.serviceInstances[plugin.identifier] = instance
                }
            }
            
            log.log("ServicePluginManager: Successfully registered plugin \(plugin.identifier)")
            
        } catch {
            log.log("ServicePluginManager: Failed to initialize plugin \(plugin.identifier): \(error)")
        }
    }
    
    // MARK: - Plugin Management
    
    /// Get all loaded plugins
    public func getAllPlugins() -> [ServicePluginInfo] {
        queue.sync {
            return loadedPlugins.values.map { ServicePluginInfo(from: $0) }
        }
    }
    
    /// Get plugins by category
    public func getPlugins(for category: ServiceCategory) -> [ServicePluginInfo] {
        queue.sync {
            return loadedPlugins.values
                .filter { $0.category == category }
                .map { ServicePluginInfo(from: $0) }
        }
    }
    
    /// Get a specific plugin
    public func getPlugin(identifier: String) -> ServicePlugin? {
        queue.sync {
            return loadedPlugins[identifier]
        }
    }
    
    /// Get a service instance
    public func getService<T>(identifier: String, type: T.Type) -> T? {
        queue.sync {
            return serviceInstances[identifier] as? T
        }
    }
    
    /// Get a service by its type (for backward compatibility)
    public func getService<T>(_ type: T.Type) -> T? where T: RegisterableService {
        return getService(identifier: T.serviceIdentifier, type: type)
    }
    
    /// Enable a plugin
    public func enablePlugin(identifier: String) -> Bool {
        guard let plugin = getPlugin(identifier: identifier) else {
            log.log("ServicePluginManager: Plugin \(identifier) not found")
            return false
        }
        
        plugin.isEnabled = true
        log.log("ServicePluginManager: Enabled plugin \(identifier)")
        return true
    }
    
    /// Disable a plugin
    public func disablePlugin(identifier: String) -> Bool {
        guard let plugin = getPlugin(identifier: identifier) else {
            log.log("ServicePluginManager: Plugin \(identifier) not found")
            return false
        }
        
        plugin.isEnabled = false
        plugin.cleanup()
        
        queue.async(flags: .barrier) {
            self.serviceInstances.removeValue(forKey: identifier)
        }
        
        log.log("ServicePluginManager: Disabled plugin \(identifier)")
        return true
    }
    
    /// Reload a plugin
    public func reloadPlugin(identifier: String) -> Bool {
        guard let plugin = getPlugin(identifier: identifier) else {
            log.log("ServicePluginManager: Plugin \(identifier) not found")
            return false
        }
        
        // Cleanup old instance
        plugin.cleanup()
        
        queue.async(flags: .barrier) {
            self.serviceInstances.removeValue(forKey: identifier)
        }
        
        // Re-initialize
        do {
            try plugin.initialize()
            
            if let instance = plugin.getServiceInstance() {
                queue.async(flags: .barrier) {
                    self.serviceInstances[identifier] = instance
                }
            }
            
            log.log("ServicePluginManager: Reloaded plugin \(identifier)")
            return true
        } catch {
            log.log("ServicePluginManager: Failed to reload plugin \(identifier): \(error)")
            return false
        }
    }
    
    /// Unload a plugin
    public func unloadPlugin(identifier: String) -> Bool {
        guard let plugin = getPlugin(identifier: identifier) else {
            log.log("ServicePluginManager: Plugin \(identifier) not found")
            return false
        }
        
        // Don't allow unloading built-in plugins
        if plugin.isBuiltIn {
            log.log("ServicePluginManager: Cannot unload built-in plugin \(identifier)")
            return false
        }
        
        plugin.cleanup()
        
        queue.async(flags: .barrier) {
            self.loadedPlugins.removeValue(forKey: identifier)
            self.serviceInstances.removeValue(forKey: identifier)
        }
        
        log.log("ServicePluginManager: Unloaded plugin \(identifier)")
        return true
    }
    
    // MARK: - Configuration
    
    /// Get configuration options for a plugin
    public func getConfigurationOptions(for identifier: String) -> [ServiceConfigOption] {
        guard let plugin = getPlugin(identifier: identifier) else {
            return []
        }
        
        return plugin.getConfigurationOptions()
    }
    
    /// Apply configuration to a plugin
    public func applyConfiguration(for identifier: String, config: [String: Any]) {
        guard let plugin = getPlugin(identifier: identifier) else {
            log.log("ServicePluginManager: Plugin \(identifier) not found")
            return
        }
        
        plugin.applyConfiguration(config)
        log.log("ServicePluginManager: Applied configuration to plugin \(identifier)")
    }
    
    /// Get saved configuration for a plugin
    public func getSavedConfiguration(for identifier: String) -> [String: Any]? {
        guard let plugin = getPlugin(identifier: identifier) else {
            log.log("ServicePluginManager: Plugin \(identifier) not found")
            return nil
        }
        
        return plugin.loadConfiguration()
    }
    
    /// Save configuration for a plugin
    public func saveConfiguration(for identifier: String, config: [String: Any]) {
        guard let plugin = getPlugin(identifier: identifier) else {
            log.log("ServicePluginManager: Plugin \(identifier) not found")
            return
        }
        
        plugin.saveConfiguration(config)
        log.log("ServicePluginManager: Saved configuration for plugin \(identifier)")
    }
    
    /// Clear configuration for a plugin
    public func clearConfiguration(for identifier: String) {
        Configuration.shared.clearPluginConfiguration(for: identifier)
        log.log("ServicePluginManager: Cleared configuration for plugin \(identifier)")
    }
    
    /// Get a specific configuration value for a plugin
    public func getConfigValue<T>(for identifier: String, key: String, type: T.Type) -> T? {
        return Configuration.shared.getPluginConfigValue(for: identifier, key: key, type: type)
    }
    
    /// Set a specific configuration value for a plugin
    public func setConfigValue(for identifier: String, key: String, value: Any?) {
        Configuration.shared.setPluginConfigValue(for: identifier, key: key, value: value)
    }
    
    // MARK: - File Watching
    
    private func setupFileWatcher() {
        let fd = open(externalPluginDirectory.path, O_EVTONLY)
        guard fd != -1 else {
            log.log("ServicePluginManager: Failed to open directory for watching")
            return
        }
        
        fileWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        
        fileWatcher?.setEventHandler { [weak self] in
            self?.handleFileSystemChange()
        }
        
        fileWatcher?.setCancelHandler {
            close(fd)
        }
        
        fileWatcher?.resume()
    }
    
    private func handleFileSystemChange() {
        log.log("ServicePluginManager: External plugin directory changed, reloading...")
        loadExternalPlugins()
    }
    
    // MARK: - Plugin Installation
    
    /// Install a plugin from a file
    public func installPlugin(from url: URL) -> (success: Bool, error: String?) {
        guard url.pathExtension == "serviceplugin" else {
            return (false, "Invalid plugin file format")
        }
        
        let destinationURL = externalPluginDirectory.appendingPathComponent(url.lastPathComponent)
        
        do {
            // Copy plugin to plugins directory
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.copyItem(at: url, to: destinationURL)
            
            // Load the plugin
            loadExternalPlugin(at: destinationURL)
            
            log.log("ServicePluginManager: Installed plugin from \(url.lastPathComponent)")
            return (true, nil)
            
        } catch {
            log.log("ServicePluginManager: Failed to install plugin: \(error)")
            return (false, error.localizedDescription)
        }
    }
    
    /// Uninstall a plugin
    public func uninstallPlugin(identifier: String) -> (success: Bool, error: String?) {
        guard let plugin = getPlugin(identifier: identifier) else {
            return (false, "Plugin not found")
        }
        
        if plugin.isBuiltIn {
            return (false, "Cannot uninstall built-in plugins")
        }
        
        // Unload the plugin first
        if !unloadPlugin(identifier: identifier) {
            return (false, "Failed to unload plugin")
        }
        
        // Find and delete the plugin file
        do {
            let pluginFiles = try FileManager.default.contentsOfDirectory(
                at: externalPluginDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            for pluginFile in pluginFiles {
                if pluginFile.lastPathComponent.contains(identifier) {
                    try FileManager.default.removeItem(at: pluginFile)
                    log.log("ServicePluginManager: Uninstalled plugin \(identifier)")
                    return (true, nil)
                }
            }
            
            return (false, "Plugin file not found")
            
        } catch {
            log.log("ServicePluginManager: Failed to uninstall plugin: \(error)")
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let servicePluginsDidChange = Notification.Name("servicePluginsDidChange")
    static let servicePluginDidLoad = Notification.Name("servicePluginDidLoad")
    static let servicePluginDidUnload = Notification.Name("servicePluginDidUnload")
}
