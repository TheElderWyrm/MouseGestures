import Foundation
import AppKit

// MARK: - PluginManagementService
// Single-purpose service for plugin management operations

class PluginManagementService {
    static let shared = PluginManagementService()
    
    private let pluginManager = PluginManager.shared
    
    private init() {}
    
    // MARK: - Plugin Information
    
    func getLoadedPlugins() -> [PluginInfo] {
        return pluginManager.getAllPlugins().map { plugin in
            let actions = pluginManager.getActionsForPlugin(identifier: plugin.identifier)
            let permissions = pluginManager.getPermissions(for: plugin.identifier) ?? .restricted
            
            return PluginInfo(
                identifier: plugin.identifier,
                name: plugin.name,
                version: plugin.version,
                author: plugin.author,
                description: plugin.description,
                category: plugin.category,
                actionCount: actions.count,
                permissions: permissions,
                isBuiltIn: permissions == .builtIn,
                isEnabled: true
            )
        }
    }
    
    func getPluginActions(_ identifier: String) -> [PluginAction] {
        return pluginManager.getActionsForPlugin(identifier: identifier)
    }
    
    // MARK: - Plugin Operations
    
    func installPlugin(from url: URL) -> (success: Bool, error: String?) {
        do {
            try pluginManager.installPlugin(from: url)
            log.log("Plugin installed from: \(url.lastPathComponent)")
            return (true, nil)
        } catch {
            let errorMessage = "Failed to install plugin: \(error.localizedDescription)"
            log.log(errorMessage)
            return (false, errorMessage)
        }
    }
    
    func uninstallPlugin(_ identifier: String) -> (success: Bool, error: String?) {
        do {
            try pluginManager.uninstallPlugin(identifier: identifier)
            log.log("Plugin uninstalled: \(identifier)")
            return (true, nil)
        } catch {
            let errorMessage = "Failed to uninstall plugin: \(error.localizedDescription)"
            log.log(errorMessage)
            return (false, errorMessage)
        }
    }
    
    func reloadPlugin(_ identifier: String) -> Bool {
        let permissions = pluginManager.getPermissions(for: identifier) ?? .restricted
        
        if permissions == .builtIn {
            let success = pluginManager.reloadBuiltInPlugin(identifier: identifier)
            log.log(success ? "Reloaded built-in plugin: \(identifier)" : "Failed to reload built-in plugin: \(identifier)")
            return success
        } else {
            let success = pluginManager.reloadExternalPlugin(identifier: identifier)
            log.log(success ? "Reloaded external plugin: \(identifier)" : "Failed to reload external plugin: \(identifier)")
            return success
        }
    }
    
    func reloadAllPlugins() {
        let plugins = getLoadedPlugins()
        
        for plugin in plugins where !plugin.isBuiltIn {
            _ = reloadPlugin(plugin.identifier)
        }
        
        log.log("All plugins reloaded")
    }
    
    // MARK: - Permissions
    
    func getPluginPermissions(_ identifier: String) -> PluginPermissions? {
        return pluginManager.getPermissions(for: identifier)
    }
    
    func updatePluginPermissions(_ identifier: String, permissions: PluginPermissions) {
        pluginManager.updatePermissions(for: identifier, permissions: permissions)
        log.log("Updated permissions for plugin \(identifier)")
    }
}
