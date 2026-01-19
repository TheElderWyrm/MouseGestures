import Cocoa
import Carbon

// MARK: - Core Actions Plugin

/// Built-in plugin providing core system actions
class CoreActionsPlugin: NSObject, GestureActionPlugin {
    
    // MARK: - Plugin Properties
    
    let identifier = "com.mousegestures.core"
    let name = "Core Actions"
    override var description: String { "Essential system and application control actions" }
    let version = "1.0.0"
    let author = "MouseGestures"
    let category = ActionCategory.system
    let icon: NSImage? = nil
    
    // MARK: - Actions
    
    lazy var providedActions: [PluginAction] = [
        PluginAction(
            id: "close_window",
            name: "Close Window",
            description: "Close the current window",
            icon: "xmark.circle"
        ),
        PluginAction(
            id: "quit_app",
            name: "Quit Application",
            description: "Quit the frontmost application",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "target",
                    name: "Target",
                    type: .selection,
                    defaultValue: AnyCodable("frontmost"),
                    description: "Which application to quit",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("frontmost"),
                        AnyCodable("specific"),
                        AnyCodable("all_except_finder")
                    ])
                ),
                ParameterDefinition(
                    key: "bundle_id",
                    name: "Bundle ID",
                    type: .string,
                    description: "Bundle ID when targeting specific app"
                )
            ],
            icon: "xmark.app"
        ),
        PluginAction(
            id: "minimize",
            name: "Minimize Window",
            description: "Minimize the current window",
            icon: "minus.circle"
        ),
        PluginAction(
            id: "maximize",
            name: "Maximize Window",
            description: "Maximize the current window",
            icon: "plus.circle"
        ),
        PluginAction(
            id: "fullscreen",
            name: "Toggle Fullscreen",
            description: "Toggle fullscreen mode",
            icon: "arrow.up.left.and.arrow.down.right"
        ),
        PluginAction(
            id: "hide_app",
            name: "Hide Application",
            description: "Hide the frontmost application",
            icon: "eye.slash"
        ),
        PluginAction(
            id: "mission_control",
            name: "Mission Control",
            description: "Show Mission Control",
            icon: "rectangle.3.group"
        ),
        PluginAction(
            id: "show_desktop",
            name: "Show Desktop",
            description: "Show the desktop",
            icon: "menubar.dock.rectangle"
        ),
        PluginAction(
            id: "app_expose",
            name: "Application Windows",
            description: "Show all windows of current application",
            icon: "rectangle.stack"
        ),
        PluginAction(
            id: "next_window",
            name: "Next Window",
            description: "Switch to next window",
            supportsRepeat: true,
            icon: "arrow.right.circle"
        ),
        PluginAction(
            id: "previous_window",
            name: "Previous Window", 
            description: "Switch to previous window",
            supportsRepeat: true,
            icon: "arrow.left.circle"
        ),
        PluginAction(
            id: "next_space",
            name: "Next Space",
            description: "Move to next desktop space",
            icon: "arrow.right.square"
        ),
        PluginAction(
            id: "previous_space",
            name: "Previous Space",
            description: "Move to previous desktop space",
            icon: "arrow.left.square"
        ),
        PluginAction(
            id: "lock_screen",
            name: "Lock Screen",
            description: "Lock the screen",
            icon: "lock"
        ),
        PluginAction(
            id: "sleep_display",
            name: "Sleep Display",
            description: "Put the display to sleep",
            icon: "moon"
        ),
        PluginAction(
            id: "empty_trash",
            name: "Empty Trash",
            description: "Empty the trash",
            icon: "trash"
        ),
        PluginAction(
            id: "next_profile",
            name: "Next Profile",
            description: "Switch to next gesture profile",
            icon: "person.crop.circle.fill.badge.plus"
        ),
        PluginAction(
            id: "previous_profile",
            name: "Previous Profile",
            description: "Switch to previous gesture profile",
            icon: "person.crop.circle.fill.badge.minus"
        ),
        PluginAction(
            id: "switch_profile",
            name: "Switch to Profile",
            description: "Switch to specific gesture profile",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "profile_id",
                    name: "Profile ID",
                    type: .string,
                    required: true,
                    description: "UUID of the profile to switch to"
                )
            ],
            icon: "person.crop.circle.fill"
        )
    ]
    
    // MARK: - Plugin Lifecycle
    
    private var context: PluginContext?
    
    func initialize(context: PluginContext) throws {
        self.context = context
        context.logger.log("Core Actions Plugin initialized", file: #file, function: #function, line: #line)
    }
    
    func cleanup() {
        context?.logger.log("Core Actions Plugin cleaned up", file: #file, function: #function, line: #line)
        context = nil
    }
    
    // MARK: - Action Execution
    
    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        guard ActionDebounce.shared.shouldExecute(action: "\(identifier).\(action.id)") else {
            context.logger.log("Action debounced: \(action.name)", file: #file, function: #function, line: #line)
            return
        }
        
        switch action.id {
        case "close_window":
            closeCurrentWindow(context: context)
        case "quit_app":
            let target = parameters.string(for: "target") ?? "frontmost"
            let bundleId = parameters.string(for: "bundle_id")
            quitApplication(target: target, bundleId: bundleId, context: context)
        case "minimize":
            minimizeWindow(context: context)
        case "maximize":
            maximizeWindow(context: context)
        case "fullscreen":
            toggleFullscreen(context: context)
        case "hide_app":
            hideApplication(context: context)
        case "mission_control":
            activateMissionControl(context: context)
        case "show_desktop":
            showDesktop(context: context)
        case "app_expose":
            activateAppExpose(context: context)
        case "next_window":
            cycleWindows(forward: true, context: context)
        case "previous_window":
            cycleWindows(forward: false, context: context)
        case "next_space":
            moveToSpace(next: true, context: context)
        case "previous_space":
            moveToSpace(next: false, context: context)
        case "lock_screen":
            lockScreen(context: context)
        case "sleep_display":
            sleepDisplay(context: context)
        case "empty_trash":
            emptyTrash(context: context)
        case "next_profile":
            switchToNextProfile(context: context)
        case "previous_profile":
            switchToPreviousProfile(context: context)
        case "switch_profile":
            if let profileIdString = parameters.string(for: "profile_id"),
               let profileId = UUID(uuidString: profileIdString) {
                switchToSpecificProfile(profileId, context: context)
            }
        default:
            throw PluginError.actionNotFound(action.id)
        }
    }
    
    func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        switch action.id {
        case "quit_app":
            if let target = parameters.string(for: "target"),
               target == "specific" && parameters.string(for: "bundle_id") == nil {
                return ValidationResult.invalid(error: "Bundle ID required when targeting specific app")
            }
        default:
            break
        }
        return .valid
    }
    
    func configurationView(for action: PluginAction) -> NSView? {
        // Return custom configuration views for actions that need them
        return nil
    }
    
    // MARK: - Private Implementation
    
    private func closeCurrentWindow(context: PluginContext) {
        guard let frontApp = context.getFrontmostApplication() else { return }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        if let windowValue = context.getAccessibilityAttribute(appElement, attribute: kAXFocusedWindowAttribute as String),
           let window = windowValue as! AXUIElement? {
            
            if let buttonValue = context.getAccessibilityAttribute(window, attribute: kAXCloseButtonAttribute as String),
               let closeButton = buttonValue as! AXUIElement? {
                _ = context.performAccessibilityAction(closeButton, action: kAXPressAction as String)
            } else {
                context.sendKeyboardShortcut(keyCode: 13, modifiers: [.maskCommand]) // Cmd+W
            }
        } else {
            context.sendKeyboardShortcut(keyCode: 13, modifiers: [.maskCommand]) // Cmd+W
        }
    }
    
    private func quitApplication(target: String, bundleId: String?, context: PluginContext) {
        switch target {
        case "frontmost":
            if let app = context.getFrontmostApplication() {
                if app.bundleIdentifier != "com.apple.finder" {
                    _ = context.terminateApplication(app)
                } else {
                    _ = context.hideApplication(app)
                }
            }
        case "specific":
            guard let bundleId = bundleId else { return }
            if bundleId != "com.apple.finder" {
                let apps = context.getRunningApplications().filter { $0.bundleIdentifier == bundleId }
                apps.forEach { _ = context.terminateApplication($0) }
            }
        case "all_except_finder":
            context.getRunningApplications().forEach { app in
                if app.activationPolicy == .regular,
                   app.bundleIdentifier != "com.apple.finder",
                   app.bundleIdentifier != Bundle.main.bundleIdentifier {
                    _ = context.terminateApplication(app)
                }
            }
        default:
            break
        }
    }
    
    private func minimizeWindow(context: PluginContext) {
        guard let frontApp = context.getFrontmostApplication() else { return }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        if let windowValue = context.getAccessibilityAttribute(appElement, attribute: kAXFocusedWindowAttribute as String),
           let window = windowValue as! AXUIElement? {
            let minimized = true as CFBoolean
            _ = context.setAccessibilityAttribute(window, attribute: kAXMinimizedAttribute as String, value: minimized)
        } else {
            context.sendKeyboardShortcut(keyCode: 46, modifiers: [.maskCommand]) // Cmd+M
        }
    }
    
    private func maximizeWindow(context: PluginContext) {
        guard let frontApp = context.getFrontmostApplication() else { return }
        guard let screen = NSScreen.main else { return }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        if let windowValue = context.getAccessibilityAttribute(appElement, attribute: kAXFocusedWindowAttribute as String),
           let window = windowValue as! AXUIElement? {
            
            let frame = screen.visibleFrame
            var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
            var size = CGSize(width: frame.size.width, height: frame.size.height)
            
            if let positionValue = AXValueCreate(.cgPoint, &position),
               let sizeValue = AXValueCreate(.cgSize, &size) {
                _ = context.setAccessibilityAttribute(window, attribute: kAXPositionAttribute as String, value: positionValue)
                _ = context.setAccessibilityAttribute(window, attribute: kAXSizeAttribute as String, value: sizeValue)
            }
        }
    }
    
    private func toggleFullscreen(context: PluginContext) {
        guard let frontApp = context.getFrontmostApplication() else { return }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        if let windowValue = context.getAccessibilityAttribute(appElement, attribute: kAXFocusedWindowAttribute as String),
           let window = windowValue as! AXUIElement? {
            if let buttonValue = context.getAccessibilityAttribute(window, attribute: kAXFullScreenButtonAttribute as String),
               let button = buttonValue as! AXUIElement? {
                _ = context.performAccessibilityAction(button, action: kAXPressAction as String)
            } else {
                context.sendKeyboardShortcut(keyCode: 3, modifiers: [.maskControl, .maskCommand]) // Ctrl+Cmd+F
            }
        }
    }
    
    private func hideApplication(context: PluginContext) {
        if let app = context.getFrontmostApplication() {
            _ = context.hideApplication(app)
        }
    }
    
    private func activateMissionControl(context: PluginContext) {
        context.sendKeyboardShortcut(keyCode: 99, modifiers: []) // F3
    }
    
    private func showDesktop(context: PluginContext) {
        context.sendKeyboardShortcut(keyCode: 103, modifiers: []) // F11
    }
    
    private func activateAppExpose(context: PluginContext) {
        context.sendKeyboardShortcut(keyCode: 125, modifiers: [.maskControl]) // Control+Down
    }
    
    private func cycleWindows(forward: Bool, context: PluginContext) {
        if forward {
            context.sendKeyboardShortcut(keyCode: 50, modifiers: [.maskCommand]) // Cmd+`
        } else {
            context.sendKeyboardShortcut(keyCode: 50, modifiers: [.maskCommand, .maskShift]) // Cmd+Shift+`
        }
    }
    
    private func moveToSpace(next: Bool, context: PluginContext) {
        let keyCode: CGKeyCode = next ? 124 : 123 // Right/Left arrow
        context.sendKeyboardShortcut(keyCode: keyCode, modifiers: [.maskControl])
    }
    
    private func lockScreen(context: PluginContext) {
        context.sendKeyboardShortcut(keyCode: 12, modifiers: [.maskCommand, .maskControl]) // Cmd+Ctrl+Q
    }
    
    private func sleepDisplay(context: PluginContext) {
        let script = "do shell script \"pmset displaysleepnow\""
        try? context.executeAppleScript(script)
    }
    
    private func emptyTrash(context: PluginContext) {
        let script = """
            tell application "Finder"
                empty trash
            end tell
        """
        try? context.executeAppleScript(script)
    }
    
    // MARK: - Helper Methods removed - now using context methods
    
    // MARK: - Profile Management
    
    private func switchToNextProfile(context: PluginContext) {
        let profiles = context.getProfiles()
        guard !profiles.isEmpty else { return }
        
        let currentId = context.getActiveProfileId()
        let currentIndex = profiles.firstIndex(where: { 
            ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == currentId 
        }) ?? 0
        
        let nextIndex = (currentIndex + 1) % profiles.count
        let nextProfile = profiles[nextIndex]
        
        if let idString = nextProfile["id"] as? String,
           let profileId = UUID(uuidString: idString),
           let profileName = nextProfile["name"] as? String {
            context.applyProfile(profileId: profileId)
            context.saveConfiguration()
            context.postNotification(name: NSNotification.Name("GestureConfigurationChanged"), userInfo: nil)
            showProfileNotification(profileName: profileName, context: context)
        }
    }
    
    private func switchToPreviousProfile(context: PluginContext) {
        let profiles = context.getProfiles()
        guard !profiles.isEmpty else { return }
        
        let currentId = context.getActiveProfileId()
        let currentIndex = profiles.firstIndex(where: { 
            ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == currentId 
        }) ?? 0
        
        let previousIndex = currentIndex > 0 ? currentIndex - 1 : profiles.count - 1
        let previousProfile = profiles[previousIndex]
        
        if let idString = previousProfile["id"] as? String,
           let profileId = UUID(uuidString: idString),
           let profileName = previousProfile["name"] as? String {
            context.applyProfile(profileId: profileId)
            context.saveConfiguration()
            context.postNotification(name: NSNotification.Name("GestureConfigurationChanged"), userInfo: nil)
            showProfileNotification(profileName: profileName, context: context)
        }
    }
    
    private func switchToSpecificProfile(_ profileId: UUID, context: PluginContext) {
        let profiles = context.getProfiles()
        guard let targetProfile = profiles.first(where: {
            ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == profileId
        }) else { return }
        
        if let profileName = targetProfile["name"] as? String {
            context.applyProfile(profileId: profileId)
            context.saveConfiguration()
            context.postNotification(name: NSNotification.Name("GestureConfigurationChanged"), userInfo: nil)
            showProfileNotification(profileName: profileName, context: context)
        }
    }
    
    private func showProfileNotification(profileName: String, context: PluginContext) {
        context.showNotification(
            title: "Profile Switched",
            message: "Active profile: \(profileName)",
            style: .info
        )
    }
}
