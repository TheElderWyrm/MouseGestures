import SwiftUI

// MARK: - Settings UI Plugin

class SettingsUIPlugin: StandardUIPlugin {
    
    // MARK: - Plugin Metadata
    
    override var identifier: String { "com.mousegestures.ui.settings" }
    override var displayName: String { "Settings" }
    override var iconName: String { "gearshape" }
    override var version: String { "1.0.0" }
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
    }
    
    @MainActor
    override func onActivate() {
        log("Settings tab activated", level: .debug)
    }
    
    override func setupObservations() async {
        // Listen for developer mode changes
        observeNotification(Notification.Name("developerModeChanged")) { [weak self] _ in
            self?.log("Developer mode changed", level: .debug)
        }
    }
}
