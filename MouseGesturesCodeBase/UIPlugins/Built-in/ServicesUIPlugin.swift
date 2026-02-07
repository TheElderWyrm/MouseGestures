import SwiftUI

// MARK: - Services UI Plugin
class ServicesUIPlugin: BaseUIPlugin {
    override var identifier: String { "com.mousegestures.ui.services" }
    override var displayName: String { "Services" }
    override var description: String { "Manage service plugins and their configuration" }
    override var iconName: String { "puzzlepiece.extension" }
    override var category: UIPluginCategory { .configuration }
    override var version: String { "1.0.0" }
    override var author: String { "MouseGestures" }
    override var sortOrder: Int { 700 }
    var isBuiltIn: Bool { true }
    override var isVisibleByDefault: Bool { false }
    
    override func createView() -> AnyView {
        AnyView(ServicesView())
    }
    
    override func shouldBeVisible(context: UIPluginContext) -> Bool {
        // Only visible when developer mode is enabled
        return context.isDeveloperModeEnabled
    }
    
    func validate() -> Bool {
        // Services view is always available
        return true
    }
    
    override func onActivate() {
        MouseGestures.log.log("ServicesUIPlugin: Activated")
    }
    
    override func onDeactivate() {
        MouseGestures.log.log("ServicesUIPlugin: Deactivated")
    }
}