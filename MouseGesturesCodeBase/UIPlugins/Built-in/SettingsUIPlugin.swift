import SwiftUI

// MARK: - Settings UI Plugin

class SettingsUIPlugin: StandardUIPlugin {
    
    // MARK: - Plugin Metadata
    
    override var identifier: String { "com.mousegestures.ui.settings" }
    override var displayName: String { "Settings" }
    override var iconName: String { "gearshape" }
    override var version: String { "2.0.0" }
    override var author: String { "MouseGestures Team" }
    override var description: String { "Configure application settings" }
    override var category: UIPluginCategory { .configuration }
    override var sortOrder: Int { 4 }
    override var requiredPermissions: UIPluginPermissions { [.configuration, .system] }
    
    // MARK: - Plugin Implementation
    
    @MainActor
    override func createView() -> AnyView {
        AnyView(SettingsView())
    }
    
    override func performInitialization() async throws {
        log("Initializing Settings UI Plugin")
        
        // Register built-in settings categories and discover service plugin settings
        await MainActor.run {
            registerBuiltInSettingsCategories()
        }
    }
    
    @MainActor
    override func onActivate() {
        log("Settings tab activated", level: .debug)
        
        // Re-discover service plugin settings in case new plugins were loaded
        registerServicePluginSettings()
    }
    
    override func setupObservations() async {
        // Listen for developer mode changes
        observeNotification(Notification.Name("developerModeChanged")) { [weak self] _ in
            self?.log("Developer mode changed", level: .debug)
        }
        
        // Listen for service plugin changes to re-discover settings providers
        observeNotification(.servicePluginsDidChange) { [weak self] _ in
            self?.log("Service plugins changed, re-discovering settings providers", level: .debug)
            DispatchQueue.main.async {
                registerServicePluginSettings()
            }
        }
    }
}
