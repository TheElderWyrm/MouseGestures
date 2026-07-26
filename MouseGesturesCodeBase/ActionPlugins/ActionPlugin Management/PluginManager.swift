import Cocoa
import UserNotifications

// MARK: - Plugin Manager

/// Manages loading, unloading, and executing plugins
public class PluginManager: NSObject {

    // MARK: - Singleton

    public static let shared = PluginManager()

    // MARK: - Properties

    private var loadedPlugins: [String: GestureActionPlugin] = [:]

    // Public accessor for loaded plugins
    public var allLoadedPlugins: [GestureActionPlugin] {
        return pluginQueue.sync { Array(loadedPlugins.values) }
    }

    // Get actions for a specific plugin
    public func getActionsForPlugin(identifier: String) -> [PluginAction] {
        return pluginQueue.sync {
            actionRegistry.compactMap { _, value in
                value.plugin.identifier == identifier ? value.action : nil
            }
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

        // Set external flag (if it's not a system plugin)
        plugin.isExternal = !isSystem

        // Initialize the plugin in sandbox
        do {
            let sandbox = PluginSandbox(plugin: plugin, permissions: permissions)
            try sandbox.initialize()

            // Store the plugin and register actions under a SYNCHRONOUS
            // barrier. sync(barrier) runs the block immediately and orders it
            // against concurrent readers, so callers (init, install) see the
            // registration complete before this returns — which init relies
            // on — and a concurrent executeAction/getAction reader can't see
            // a half-populated actionRegistry.
            pluginQueue.sync(flags: .barrier) {
                self.loadedPlugins[plugin.identifier] = plugin
                self.sandboxedPlugins[plugin.identifier] = sandbox
                self.pluginPermissions[plugin.identifier] = permissions
                self.pluginBundles[plugin.identifier] = bundle

                // Register actions
                for action in plugin.providedActions {
                    let actionId = "\(plugin.identifier).\(action.id)"
                    self.actionRegistry[actionId] = (plugin, action)
                }
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
            (WindowManagementPlugin(), .builtIn),
            (MediaControlPlugin(), .builtIn),
            (BrowserActionsPlugin(), .builtIn),
            (SystemControlPlugin(), .builtIn),
            (AutomationPlugin(), .builtIn),
            (BundleActionsPlugin(), .builtIn)
        ]

        for (plugin, permissions) in builtInPlugins {
            do {
                // Built-in plugins are never external
                plugin.isExternal = false

                // Create sandboxed wrapper
                let sandbox = PluginSandbox(plugin: plugin, permissions: permissions)
                try sandbox.initialize()

                // Store under a synchronous barrier (see loadPlugin). Runs once
                // at init, before any gesture can fire.
                pluginQueue.sync(flags: .barrier) {
                    self.loadedPlugins[plugin.identifier] = plugin
                    self.sandboxedPlugins[plugin.identifier] = sandbox
                    self.pluginPermissions[plugin.identifier] = permissions

                    // Register actions
                    for action in plugin.providedActions {
                        let actionId = "\(plugin.identifier).\(action.id)"
                        self.actionRegistry[actionId] = (plugin, action)
                    }
                }

                log.log("Loaded built-in plugin: \(plugin.name) (sandboxed)")
            } catch {
                log.log("Failed to load built-in plugin \(plugin.name): \(error)")
            }
        }
    }

    // MARK: - Plugin Reload

    /// Reload a built-in plugin by re-instantiating and re-registering it
    public func reloadBuiltInPlugin(identifier: String) -> Bool {
        guard getPlugin(identifier: identifier) != nil else {
            log.log("Cannot reload: plugin \(identifier) not found")
            return false
        }

        // Map identifier to a fresh instance of the built-in plugin
        let builtInMap: [String: () -> GestureActionPlugin] = [
            "com.mousegestures.window": { WindowManagementPlugin() },
            "com.mousegestures.media": { MediaControlPlugin() },
            "com.mousegestures.browser": { BrowserActionsPlugin() },
            "com.mousegestures.system": { SystemControlPlugin() },
            "com.mousegestures.automation": { AutomationPlugin() },
            "com.mousegestures.bundle": { BundleActionsPlugin() }
        ]
        guard let factory = builtInMap[identifier] else {
            log.log("Plugin \(identifier) is not a recognized built-in plugin")
            return false
        }

        // Unload old instance
        unloadPlugin(identifier: identifier)

        // Create and register fresh instance
        let plugin = factory()
        do {
            let sandbox = PluginSandbox(plugin: plugin, permissions: .builtIn)
            try sandbox.initialize()

            // Register under a barrier, ordered after unloadPlugin's removal
            // barrier (barriers on the same queue execute in submission order),
            // so readers never see the old plugin's entries interleaved with
            // the new ones.
            pluginQueue.async(flags: .barrier) {
                self.loadedPlugins[plugin.identifier] = plugin
                self.sandboxedPlugins[plugin.identifier] = sandbox
                self.pluginPermissions[plugin.identifier] = .builtIn

                for action in plugin.providedActions {
                    let actionId = "\(plugin.identifier).\(action.id)"
                    self.actionRegistry[actionId] = (plugin, action)
                }
            }

            lifecycleDelegates.forEach { $0.pluginDidLoad(plugin) }
            log.log("Successfully reloaded built-in plugin: \(plugin.name)")
            return true
        } catch {
            log.log("Failed to reload built-in plugin \(plugin.name): \(error)")
            return false
        }
    }

    /// Reload an external plugin from its bundle
    public func reloadExternalPlugin(identifier: String) -> Bool {
        let bundle = pluginQueue.sync { pluginBundles[identifier] }
        guard let bundle = bundle else {
            log.log("Cannot reload external plugin \(identifier): no bundle found")
            return false
        }

        let bundleURL = bundle.bundleURL
        let wasSystem = pluginQueue.sync { pluginPermissions[identifier] } == .default

        // Unload the plugin (this also unloads the bundle)
        unloadPlugin(identifier: identifier)

        // Reload from disk
        loadPlugin(at: bundleURL, isSystem: wasSystem)
        return getPlugin(identifier: identifier) != nil
    }

    // MARK: - Plugin Unloading

    public func unloadPlugin(identifier: String) {
        // Snapshot the plugin under the reader lock, then perform cleanup
        // (which can call back into arbitrary plugin code) OUTSIDE the lock,
        // and finally mutate the registries under a barrier so a concurrent
        // executeAction/getAction reader can't see a half-removed plugin.
        let plugin: GestureActionPlugin? = pluginQueue.sync {
            loadedPlugins[identifier]
        }
        guard let plugin = plugin else {
            log.log("Plugin not found: \(identifier)")
            return
        }
        let sandbox = pluginQueue.sync { sandboxedPlugins[identifier] }
        let bundle = pluginQueue.sync { pluginBundles[identifier] }

        // Notify delegates
        lifecycleDelegates.forEach { $0.pluginWillUnload(plugin) }

        // Clean up the sandbox first
        sandbox?.cleanup()

        // Clean up the plugin
        plugin.cleanup()

        // Unload the bundle if it exists
        bundle?.unload()

        // Remove from registries under a barrier (serializes with readers).
        pluginQueue.async(flags: .barrier) {
            self.loadedPlugins.removeValue(forKey: identifier)
            self.sandboxedPlugins.removeValue(forKey: identifier)
            self.pluginPermissions.removeValue(forKey: identifier)
            self.pluginBundles.removeValue(forKey: identifier)
            // Remove actions
            self.actionRegistry = self.actionRegistry.filter { !$0.key.hasPrefix("\(identifier).") }
        }

        log.log("Unloaded plugin: \(plugin.name)")
    }

    // MARK: - Plugin Execution

    public func executeAction(identifier: String, parameters: ActionParameters = ActionParameters()) throws {
        // Snapshot the (plugin, action, sandbox) under the reader lock so a
        // concurrent unloadPlugin/reload (which mutates these under a barrier)
        // can't release a plugin mid-execute or hand back a torn registry entry.
        // Execute OUTSIDE the lock so plugin code can re-enter PluginManager
        // (e.g. executeActionFromPlugin) without deadlocking.
        let snapshot: (plugin: GestureActionPlugin, action: PluginAction, sandbox: PluginSandbox?)? =
            pluginQueue.sync {
                guard let entry = actionRegistry[identifier] else { return nil }
                return (entry.plugin, entry.action, sandboxedPlugins[entry.plugin.identifier])
            }
        guard let (plugin, action, sandbox) = snapshot else {
            throw PluginError.actionNotFound(identifier)
        }

        // Use sandboxed execution if available
        if let sandbox = sandbox {
            // Execute through sandbox for safety
            try sandbox.executeAction(action, with: parameters)
        } else {
            // This should never happen - all plugins should have sandboxes
            throw PluginError.executionFailed("Plugin \(plugin.identifier) has no sandbox!")
        }
    }

    /// Execute an action requested by another plugin (with permission checking)
    internal func executeActionFromPlugin(identifier: String, parameters: ActionParameters, requestingPlugin: String) {
        // Check if requesting plugin has permission (read under the lock).
        guard let permissions = getPermissions(for: requestingPlugin),
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
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        // Map style to a subtitle note (optional)
        switch style {
        case .warning: content.subtitle = "⚠️"
        case .error:   content.subtitle = "❌"
        default: break
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil   // nil = deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                log.log("Notification delivery failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Permission Management

    /// Update permissions for a specific plugin
    public func updatePermissions(for pluginId: String, permissions: PluginPermissions) {
        // Snapshot the current plugin + its old sandbox under the reader lock.
        let (plugin, oldSandbox): (GestureActionPlugin?, PluginSandbox?) = pluginQueue.sync {
            (loadedPlugins[pluginId], sandboxedPlugins[pluginId])
        }

        // Build + initialize the replacement sandbox OUTSIDE the barrier. Two
        // reasons: (1) initialize() re-runs plugin.initialize(context:) so the
        // plugin re-binds to the new context and re-registers any notification
        // observers under the NEW permissions — without this the permission
        // change never takes effect for anything the plugin captured at load
        // time; (2) plugin.initialize can re-enter PluginManager, so running it
        // inside a pluginQueue barrier could deadlock.
        var newSandbox: PluginSandbox?
        if let plugin = plugin {
            let sandbox = PluginSandbox(plugin: plugin, permissions: permissions)
            do {
                try sandbox.initialize()
                newSandbox = sandbox
            } catch {
                // Keep the old sandbox in place on failure rather than leaving
                // the plugin with no working sandbox.
                log.log("updatePermissions: failed to initialize new sandbox for '\(pluginId)': \(error)")
            }
        }

        // Publish the new permissions (and sandbox, if one was built) under a
        // synchronous barrier so the replacement is guaranteed in place before
        // we retire the old context below (and so concurrent readers can't see
        // a torn state). Safe from a sync barrier here: updatePermissions is
        // never called from within pluginQueue.
        pluginQueue.sync(flags: .barrier) {
            self.pluginPermissions[pluginId] = permissions
            if let newSandbox = newSandbox {
                self.sandboxedPlugins[pluginId] = newSandbox
            }
        }

        // Only once the replacement is in place: retire the OLD sandbox's
        // context so its NotificationCenter observers are removed (otherwise
        // they leak and keep reacting under the stale permissions). This does
        // NOT call plugin.cleanup() — the plugin instance stays loaded.
        if newSandbox != nil {
            oldSandbox?.discardContext()
        }

        log.log("Updated permissions for plugin '\(pluginId)'")
    }

    /// Get current permissions for a plugin
    public func getPermissions(for pluginId: String) -> PluginPermissions? {
        return pluginQueue.sync { pluginPermissions[pluginId] }
    }

    // MARK: - Plugin Query

    public func getAllPlugins() -> [GestureActionPlugin] {
        pluginQueue.sync { Array(loadedPlugins.values) }
    }

    public func getPlugin(identifier: String) -> GestureActionPlugin? {
        pluginQueue.sync { loadedPlugins[identifier] }
    }

    public func getAllActions() -> [(pluginId: String, action: PluginAction)] {
        pluginQueue.sync {
            actionRegistry.compactMap { _, value in
                // Use the stored plugin's actual identifier rather than
                // reconstructing it by splitting the compound key on ".". The old
                // reconstruction mis-parsed any action id that itself contains a
                // dot (e.g. an action id "system.mute" under plugin
                // "com.mousegestures.core" produced plugin id
                // "com.mousegestures.core.system" — wrong).
                return (value.plugin.identifier, value.action)
            }
        }
    }

    public func getActionsForCategory(_ category: ActionCategory) -> [(plugin: GestureActionPlugin, action: PluginAction)] {
        pluginQueue.sync {
            loadedPlugins.values.flatMap { plugin -> [(GestureActionPlugin, PluginAction)] in
                guard plugin.category == category else { return [] }
                return plugin.providedActions.map { (plugin, $0) }
            }
        }
    }

    public func getAction(identifier: String) -> (plugin: GestureActionPlugin, action: PluginAction)? {
        pluginQueue.sync { actionRegistry[identifier] }
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
        guard let bundle = pluginQueue.sync(execute: { pluginBundles[identifier] }) else {
            throw PluginError.actionNotFound(identifier)
        }

        // Unload the plugin first
        unloadPlugin(identifier: identifier)

        // Delete the plugin bundle
        try fileManager.removeItem(at: bundle.bundleURL)
    }

    // MARK: - Configuration

    public func getConfigurationView(for actionIdentifier: String) -> NSView? {
        guard let (plugin, action) = pluginQueue.sync(execute: { actionRegistry[actionIdentifier] }) else {
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

        case .accessFile:
            // Handle file access request
            completion(.failure(PluginSandboxError.permissionDenied("File access not implemented")))

        case .openURL(let url):
            NSWorkspace.shared.open(url)
            completion(.success(nil))

        case .accessSystemAPI:
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
