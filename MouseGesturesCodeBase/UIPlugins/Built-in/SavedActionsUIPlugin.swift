import SwiftUI

// MARK: - Saved Actions UI Plugin

class SavedActionsUIPlugin: StandardUIPlugin {
    
    // MARK: - Plugin Metadata
    
    override var identifier: String { "com.mousegestures.ui.savedactions" }
    override var displayName: String { "Saved Actions" }
    override var iconName: String { "square.and.arrow.down" }
    override var version: String { "1.0.0" }
    override var author: String { "MouseGestures Team" }
    override var description: String { "Manage saved action templates" }
    override var category: UIPluginCategory { .core }
    override var sortOrder: Int { 1 }
    override var requiredPermissions: UIPluginPermissions { [.actions] }
    
    // MARK: - Plugin Implementation
    
    @MainActor
    override func createView() -> AnyView {
        AnyView(SavedActionsView())
    }
    
    override func performInitialization() async throws {
        log("Initializing Saved Actions UI Plugin")
    }
    
    @MainActor
    override func onActivate() {
        log("Saved Actions tab activated", level: .debug)
        // Refresh saved actions when tab becomes active
        context?.uiServices.loadData()
    }
}
