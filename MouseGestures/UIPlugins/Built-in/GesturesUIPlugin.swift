import SwiftUI

// MARK: - Gestures UI Plugin

class GesturesUIPlugin: StandardUIPlugin {
    
    // MARK: - Plugin Metadata
    
    override var identifier: String { "com.mousegestures.ui.gestures" }
    override var displayName: String { "Gestures" }
    override var iconName: String { "hand.draw.fill" }
    override var version: String { "1.0.0" }
    override var author: String { "MouseGestures Team" }
    override var description: String { "Manage and configure mouse gestures" }
    override var category: UIPluginCategory { .core }
    override var sortOrder: Int { 0 }
    override var requiredPermissions: UIPluginPermissions { [.gestures, .profiles, .actions] }
    
    // MARK: - Plugin Implementation
    
    @MainActor
    override func createView() -> AnyView {
        AnyView(GesturesView())
    }
    
    override func performInitialization() async throws {
        log("Initializing Gestures UI Plugin")
        
        // Load gesture data
        await MainActor.run {
            context?.uiServices.loadData()
        }
    }
    
    @MainActor
    override func onActivate() {
        log("Gestures tab activated", level: .debug)
        // Refresh data when tab becomes active
        context?.uiServices.loadData()
    }
}
