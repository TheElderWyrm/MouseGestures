import Cocoa

// MARK: - Plugin Manager

/// Manages loading, unloading, and executing plugins
public class PluginManager: NSObject {

    // MARK: - Singleton
    
    public static let shared = PluginManager()
    
    // MARK: - Properties
    
    private var loadedPlugins: [String: GestureActionPlugin] = [:]
    
    // Public accessor for loaded plugins
    public var allLoadedPlugins: [GestureActionPlugin] {
        return Array(loadedPlugins.values)
    }
    
    // Get actions for a specific plugin
    public func getActionsForPlugin(identifier: String) -> [PluginAction] {
        return actionRegistry.compactMap { key, value in
            value.plugin.identifier == identifier ? value.action : nil
        }
    }
    internal var sandboxedPlugins: [String: PluginSandbox] = [:] // Sandboxed wrappers
    private var pluginBundles: [String: Bundle] = [:]
    private var actionRegistry: [String: (plugin: GestureActionPlugin, action: PluginAction)] = [:]
    private var lifecycleDelegates: [PluginLifecycleDelegate] = []
    private let pluginQueue = DispatchQueue(label: "com.mousegestures.plugins", attributes: .concurrent)
    private var pluginPermissions: [String: PluginPermissions] = [:] // Permissions per plugin
    
    // Directories
    private let systemPluginsDirectory: URL
    private let userPluginsDirectory: URL
    
    // Plugin discovery
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    private override init() {
        // Set up plugin directories
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("MouseGestures", isDirectory: true)
        
        self.userPluginsDirectory = appDirectory.appendingPathComponent("Plugins", isDirectory: true)
        
        // System plugins are in the app bundle
        if let resourcePath = Bundle.main.resourcePath {
            self.systemPluginsDirectory = URL(fileURLWithPath: resourcePath).appendingPathComponent("Plugins", isDirectory: true)
        } else {
            self.systemPluginsDirectory = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Plugins", isDirectory: true)
        }
        
        super.init()
        
        // Create directories if needed
        createPluginDirectories()
        
        // Load built-in plugins
        loadBuiltInPlugins()
        
        // Discover and load external plugins
        discoverAndLoadPlugins()
    }
    
    // MARK: - Directory Management
    
    private func createPluginDirectories() {
        do {
            if !fileManager.fileExists(atPath: userPluginsDirectory.path) {
                try fileManager.createDirectory(at: userPluginsDirectory, withIntermediateDirectories: true)
                log.log("Created user plugins directory at: \(userPluginsDirectory.path)")
            }
        } catch {
            log.log("Failed to create plugin directories: \(error)")
        }
    }
    
    // MARK: - Plugin Discovery
    
    private func discoverAndLoadPlugins() {
        log.log("Discovering plugins...")
        
        // Discover system plugins
        discoverPluginsIn(directory: systemPluginsDirectory, isSystem: true)
        
        // Discover user plugins
        discoverPluginsIn(directory: userPluginsDirectory, isSystem: false)
        
        log.log("Plugin discovery complete. Loaded \(loadedPlugins.count) plugins.")
    }
    
    private func discoverPluginsIn(directory: URL, isSystem: Bool) {
        guard fileManager.fileExists(atPath: directory.path) else {
            log.log("Plugin directory does not exist: \(directory.path)")
            return
        }
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            
            for item in contents {
                if item.pathExtension == "plugin" || item.pathExtension == "bundle" {
                    loadPlugin(at: item, isSystem: isSystem)
                }
            }
        } catch {
            log.log("Error discovering plugins in \(directory.path): \(error)")
        }
    }
    
    // MARK: - Plugin Loading
    
    private func loadPlugin(at url: URL, isSystem: Bool) {
        log.log("Loading plugin at: \(url.path)")
        
        guard let bundle = Bundle(url: url) else {
            log.log("Failed to create bundle for plugin at: \(url.path)")
            return
        }
        
        // Load the bundle
        guard bundle.load() else {
            log.log("Failed to load bundle for plugin at: \(url.path)")
            return
        }
        
        // Get the principal class, which must be an NSObject subclass
        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            log.log("No principal class found in plugin at: \(url.path)")
            bundle.unload()
            return
        }
        
        // Instantiate the class and check if the instance conforms to our protocol
        guard let plugin = principalClass.init() as? GestureActionPlugin else {
            log.log("Principal class '\(principalClass)' does not conform to GestureActionPlugin protocol or failed to instantiate.")
            bundle.unload()
            return
        }
        
        // Determine permissions for external plugin
        let permissions = isSystem ? PluginPermissions.default : PluginPermissions.restricted
        
        // Initialize the plugin in sandbox
        do {
            let sandbox = PluginSandbox(plugin: plugin, permissions: permissions)
            try sandbox.initialize()
            
            // Store the plugin and sandbox
            loadedPlugins[plugin.identifier] = plugin
            sandboxedPlugins[plugin.identifier] = sandbox
            pluginPermissions[plugin.identifier] = permissions
            pluginBundles[plugin.identifier] = bundle
            
            // Register actions
            for action in plugin.providedActions {
                let actionId = "\(plugin.identifier).\(action.id)"
                actionRegistry[actionId] = (plugin, action)
            }
            
            // Notify delegates
            lifecycleDelegates.forEach { $0.pluginDidLoad(plugin) }
            
            log.log("Successfully loaded plugin: \(plugin.name) v\(plugin.version) (sandboxed)")
        } catch {
            log.log("Failed to initialize plugin \(plugin.name): \(error)")
            lifecycleDelegates.forEach { $0.plugin(plugin, didFailWithError: error) }
            bundle.unload() // Unload if initialization fails
        }
    }
    
    private func loadBuiltInPlugins() {
        // Register built-in plugins with appropriate permissions
        let builtInPlugins: [(plugin: GestureActionPlugin, permissions: PluginPermissions)] = [
            (CoreActionsPlugin(), .builtIn),
            (WindowManagementPlugin(), .builtIn),
            (MediaControlPlugin(), .builtIn),
            (SystemControlPlugin(), .builtIn),
            (AutomationPlugin(), .builtIn),
            (BundleActionsPlugin(), .builtIn)
        ]
        
        for (plugin, permissions) in builtInPlugins {
            do {
                // Create sandboxed wrapper
                let sandbox = PluginSandbox(plugin: plugin, permissions: permissions)
                try sandbox.initialize()
                
                // Store both the plugin and its sandbox
                loadedPlugins[plugin.identifier] = plugin
                sandboxedPlugins[plugin.identifier] = sandbox
                pluginPermissions[plugin.identifier] = permissions
                
                // Register actions
                for action in plugin.providedActions {
                    let actionId = "\(plugin.identifier).\(action.id)"
                    actionRegistry[actionId] = (plugin, action)
                }
                
                log.log("Loaded built-in plugin: \(plugin.name) (sandboxed)")
            } catch {
                log.log("Failed to load built-in plugin \(plugin.name): \(error)")
            }
        }
    }
    
    // MARK: - Plugin Unloading
    
    public func unloadPlugin(identifier: String) {
        guard let plugin = loadedPlugins[identifier] else {
            log.log("Plugin not found: \(identifier)")
            return
        }
        
        // Notify delegates
        lifecycleDelegates.forEach { $0.pluginWillUnload(plugin) }
        
        // Clean up the sandbox first
        if let sandbox = sandboxedPlugins[identifier] {
            sandbox.cleanup()
        }
        
        // Clean up the plugin
        plugin.cleanup()
        
        // Unload the bundle if it exists
        if let bundle = pluginBundles[identifier] {
            bundle.unload()
        }
        
        // Remove from registry
        loadedPlugins.removeValue(forKey: identifier)
        sandboxedPlugins.removeValue(forKey: identifier)
        pluginPermissions.removeValue(forKey: identifier)
        pluginBundles.removeValue(forKey: identifier)
        
        // Remove actions
        actionRegistry = actionRegistry.filter { !$0.key.hasPrefix("\(identifier).") }
        
        log.log("Unloaded plugin: \(plugin.name)")
    }
    
    // MARK: - Plugin Execution
    
    public func executeAction(identifier: String, parameters: ActionParameters = ActionParameters()) throws {
        guard let (plugin, action) = actionRegistry[identifier] else {
            throw PluginError.actionNotFound(identifier)
        }
        
        // Use sandboxed execution if available
        if let sandbox = sandboxedPlugins[plugin.identifier] {
            // Execute through sandbox for safety
            try sandbox.executeAction(action, with: parameters)
        } else {
            // This should never happen - all plugins should have sandboxes
            throw PluginError.executionFailed("Plugin \(plugin.identifier) has no sandbox!")
        }
    }
    
    /// Execute an action requested by another plugin (with permission checking)
    internal func executeActionFromPlugin(identifier: String, parameters: ActionParameters, requestingPlugin: String) {
        // Check if requesting plugin has permission
        guard let permissions = pluginPermissions[requestingPlugin],
              permissions.canExecuteOtherActions else {
            log.log("⚠️ Plugin '\(requestingPlugin)' denied permission to execute action '\(identifier)'")
            return
        }
        
        // Log the cross-plugin execution
        log.log("Plugin '\(requestingPlugin)' executing action '\(identifier)'")
        
        // Execute the action
        do {
            try executeAction(identifier: identifier, parameters: parameters)
        } catch {
            log.log("Failed to execute action '\(identifier)' requested by plugin '\(requestingPlugin)': \(error)")
        }
    }
    
    /// Show a notification from a plugin
    internal func showPluginNotification(title: String, message: String, style: NotificationStyle, pluginId: String) {
        // This is called from SandboxedPluginContext to show notifications
        DispatchQueue.main.async {
            let notification = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            
            notification.isOpaque = false
            
            // Set background color based on style
            switch style {
            case .info:
                notification.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.9)
            case .success:
                notification.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.9)
            case .warning:
                notification.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.9)
            case .error:
                notification.backgroundColor = NSColor.systemRed.withAlphaComponent(0.9)
            }
            
            notification.level = .floating
            notification.hasShadow = true
            notification.isReleasedWhenClosed = false
            notification.ignoresMouseEvents = true
            
            // Title label (includes plugin attribution)
            let titleLabel = NSTextField(frame: NSRect(x: 20, y: 50, width: 360, height: 25))
            titleLabel.stringValue = title
            titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
            titleLabel.textColor = .white
            titleLabel.backgroundColor = .clear
            titleLabel.isBordered = false
            titleLabel.isEditable = false
            
            // Message label
            let messageLabel = NSTextField(frame: NSRect(x: 20, y: 20, width: 360, height: 25))
            messageLabel.stringValue = message
            messageLabel.font = NSFont.systemFont(ofSize: 14)
            messageLabel.textColor = .white
            messageLabel.backgroundColor = .clear
            messageLabel.isBordered = false
            messageLabel.isEditable = false
            
            notification.contentView?.addSubview(titleLabel)
            notification.contentView?.addSubview(messageLabel)
            
            // Center on screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - notification.frame.width / 2
                let y = screenFrame.maxY - notification.frame.height - 50
                notification.setFrameOrigin(NSPoint(x: x, y: y))
            }
            
            // Show and fade out
            notification.orderFront(nil)
            notification.alphaValue = 0
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                notification.animator().alphaValue = 1.0
            }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.3
                        notification.animator().alphaValue = 0
                    }) {
                        notification.close()
                    }
                }
            }
        }
    }
    
    // MARK: - Permission Management
    
    /// Update permissions for a specific plugin
    public func updatePermissions(for pluginId: String, permissions: PluginPermissions) {
        pluginPermissions[pluginId] = permissions
        
        // If plugin is loaded, update its sandbox
        if let plugin = loadedPlugins[pluginId] {
            // Recreate sandbox with new permissions
            sandboxedPlugins[pluginId] = PluginSandbox(plugin: plugin, permissions: permissions)
        }
        
        log.log("Updated permissions for plugin '\(pluginId)'")
    }
    
    /// Get current permissions for a plugin
    public func getPermissions(for pluginId: String) -> PluginPermissions? {
        return pluginPermissions[pluginId]
    }
    
    // MARK: - Plugin Query
    
    public func getAllPlugins() -> [GestureActionPlugin] {
        Array(loadedPlugins.values)
    }
    
    public func getPlugin(identifier: String) -> GestureActionPlugin? {
        loadedPlugins[identifier]
    }
    
    public func getAllActions() -> [(pluginId: String, action: PluginAction)] {
        actionRegistry.compactMap { key, value in
            let components = key.split(separator: ".")
            guard components.count >= 2 else { return nil }
            // Reconstruct the plugin identifier in case it contains dots.
            let pluginId = components.dropLast().joined(separator: ".")
            return (pluginId, value.action)
        }
    }
    
    public func getActionsForCategory(_ category: ActionCategory) -> [(plugin: GestureActionPlugin, action: PluginAction)] {
        loadedPlugins.values.flatMap { plugin -> [(GestureActionPlugin, PluginAction)] in
            guard plugin.category == category else { return [] }
            return plugin.providedActions.map { (plugin, $0) }
        }
    }
    
    public func getAction(identifier: String) -> (plugin: GestureActionPlugin, action: PluginAction)? {
        actionRegistry[identifier]
    }
    
    // MARK: - Lifecycle Delegates
    
    public func addLifecycleDelegate(_ delegate: PluginLifecycleDelegate) {
        lifecycleDelegates.append(delegate)
    }
    
    public func removeLifecycleDelegate(_ delegate: PluginLifecycleDelegate) {
        lifecycleDelegates.removeAll { $0 === delegate }
    }
    
    // MARK: - Plugin Installation
    
    public func installPlugin(from url: URL) throws {
        let pluginName = url.lastPathComponent
        let destination = userPluginsDirectory.appendingPathComponent(pluginName)
        
        // Copy the plugin to the user plugins directory
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        
        try fileManager.copyItem(at: url, to: destination)
        
        // Load the plugin
        loadPlugin(at: destination, isSystem: false)
    }
    
    public func uninstallPlugin(identifier: String) throws {
        guard let bundle = pluginBundles[identifier] else {
            throw PluginError.actionNotFound(identifier)
        }
        
        // Unload the plugin first
        unloadPlugin(identifier: identifier)
        
        // Delete the plugin bundle
        try fileManager.removeItem(at: bundle.bundleURL)
    }
    
    // MARK: - Configuration
    
    public func getConfigurationView(for actionIdentifier: String) -> NSView? {
        guard let (plugin, action) = actionRegistry[actionIdentifier] else {
            return nil
        }
        
        return plugin.configurationView(for: action)
    }
}

// MARK: - Plugin Request Handler Implementation

class PluginRequestHandlerImpl: PluginRequestHandler {
    
    func handleRequest(_ request: PluginRequest, completion: @escaping (Result<Any?, Error>) -> Void) {
        // Log the request
        log.log("Plugin '\(request.pluginId)' requesting: \(request.type)")
        
        // Check if should auto-approve
        if shouldAutoApprove(request) {
            // Execute the request
            executeRequest(request, completion: completion)
        } else {
            // Show user prompt for approval
            promptUserForApproval(request) { approved in
                if approved {
                    self.executeRequest(request, completion: completion)
                } else {
                    completion(.failure(PluginSandboxError.permissionDenied("User denied request")))
                }
            }
        }
    }
    
    func shouldAutoApprove(_ request: PluginRequest) -> Bool {
        // Built-in plugins can auto-approve certain requests
        if let permissions = PluginManager.shared.getPermissions(for: request.pluginId),
           permissions.canAccessSystemAPIs {
            return true
        }
        
        // Otherwise require user approval
        return false
    }
    
    private func executeRequest(_ request: PluginRequest, completion: @escaping (Result<Any?, Error>) -> Void) {
        switch request.type {
        case .executeAction(let identifier, let parameters):
            do {
                try PluginManager.shared.executeAction(identifier: identifier, parameters: parameters)
                completion(.success(nil))
            } catch {
                completion(.failure(error))
            }
            
        case .accessFile(_, _):
            // Handle file access request
            completion(.failure(PluginSandboxError.permissionDenied("File access not implemented")))
            
        case .openURL(let url):
            NSWorkspace.shared.open(url)
            completion(.success(nil))
            
        case .accessSystemAPI(_):
            // Handle system API access
            completion(.failure(PluginSandboxError.permissionDenied("System API access not implemented")))
            
        case .elevatePermissions(let permissions):
            // Handle permission elevation request
            PluginManager.shared.updatePermissions(for: request.pluginId, permissions: permissions)
            completion(.success(nil))
        }
    }
    
    private func promptUserForApproval(_ request: PluginRequest, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Plugin Request"
            alert.informativeText = "Plugin '\(request.pluginId)' is requesting permission:\n\n\(request.reason ?? "No reason provided")"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Deny")
            
            let response = alert.runModal()
            completion(response == .alertFirstButtonReturn)
        }
    }
}
