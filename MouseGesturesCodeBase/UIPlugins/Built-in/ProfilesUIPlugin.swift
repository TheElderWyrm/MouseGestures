import SwiftUI

// MARK: - Profiles UI Plugin

class ProfilesUIPlugin: StandardUIPlugin {
    
    // MARK: - Plugin Metadata
    
    override var identifier: String { "com.mousegestures.ui.profiles" }
    override var displayName: String { "Profiles" }
    override var iconName: String { "person.2" }
    override var version: String { "1.0.0" }
    override var author: String { "MouseGestures Team" }
    override var description: String { "Manage gesture profiles" }
    override var category: UIPluginCategory { .configuration }
    override var sortOrder: Int { 2 }
    override var isPro: Bool { true }
    override var requiredPermissions: UIPluginPermissions { [.profiles, .gestures] }
    
    // MARK: - Plugin Implementation
    
    @MainActor
    override func createView() -> AnyView {
        AnyView(ProfilesView())
    }
    
    override func performInitialization() async throws {
        log("Initializing Profiles UI Plugin")
    }
    
    @MainActor
    override func onActivate() {
        log("Profiles tab activated", level: .debug)
        // Refresh profiles when tab becomes active
        context?.uiServices.loadData()
    }
    
    override func setupObservations() async {
        // Listen for profile changes
        observeNotification(.profilesDidChange) { [weak self] _ in
            self?.log("Profiles changed", level: .debug)
        }
    }
}
