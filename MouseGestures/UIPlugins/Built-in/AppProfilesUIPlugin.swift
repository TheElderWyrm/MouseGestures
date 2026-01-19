import SwiftUI

// MARK: - App Profiles UI Plugin

class AppProfilesUIPlugin: StandardUIPlugin {
    
    // MARK: - Plugin Metadata
    
    override var identifier: String { "com.mousegestures.ui.appprofiles" }
    override var displayName: String { "App Profiles" }
    override var iconName: String { "app.badge" }
    override var version: String { "1.0.0" }
    override var author: String { "MouseGestures Team" }
    override var description: String { "Configure app-specific gesture profiles" }
    override var category: UIPluginCategory { .configuration }
    override var sortOrder: Int { 3 }
    override var requiredPermissions: UIPluginPermissions { [.profiles, .configuration] }
    
    // MARK: - Plugin Implementation
    
    @MainActor
    override func createView() -> AnyView {
        AnyView(AppProfilesView())
    }
    
    override func performInitialization() async throws {
        log("Initializing App Profiles UI Plugin")
    }
    
    @MainActor
    override func onActivate() {
        log("App Profiles tab activated", level: .debug)
        // Refresh app profile mappings when tab becomes active
        context?.uiServices.loadData()
    }
}
