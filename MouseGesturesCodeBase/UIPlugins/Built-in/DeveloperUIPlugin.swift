import SwiftUI

// MARK: - Developer UI Plugin

class DeveloperUIPlugin: DeveloperUIPluginBase {
    
    // MARK: - Plugin Metadata
    
    override var identifier: String { "com.mousegestures.ui.developer" }
    override var displayName: String { "Developer" }
    override var iconName: String { "wrench.and.screwdriver" }
    override var version: String { "1.0.0" }
    override var author: String { "MouseGestures Team" }
    override var description: String { "Developer tools and debugging" }
    override var sortOrder: Int { 5 }
    
    // MARK: - Plugin Implementation
    
    @MainActor
    override func createView() -> AnyView {
        AnyView(DeveloperView())
    }
    
    override func performInitialization() async throws {
        log("Initializing Developer UI Plugin")
    }
    
    @MainActor
    override func onActivate() {
        log("Developer tab activated", level: .debug)
        
        // Start performance monitoring when developer tab is active
        verbose("Starting performance monitoring")
    }
    
    @MainActor
    override func onDeactivate() {
        log("Developer tab deactivated", level: .debug)
        
        // Stop performance monitoring when developer tab is inactive
        verbose("Stopping performance monitoring")
    }
    
    override func setupObservations() async {
        // Listen for debug events
        observeNotification(Notification.Name("debugEventOccurred")) { [weak self] notification in
            if let event = notification.userInfo?["event"] as? String {
                self?.debug("Debug event: \(event)")
            }
        }
    }
}
