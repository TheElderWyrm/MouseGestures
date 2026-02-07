import Cocoa

// MARK: - System Control Plugin

/// Built-in plugin for system control actions
class SystemControlPlugin: NSObject, GestureActionPlugin {
    
    // MARK: - Plugin Properties
    
    let identifier = "com.mousegestures.system"
    let name = "System Control"
    override var description: String { "Control system settings and display" }
    let version = "1.0.0"
    let author = "MouseGestures"
    let category = ActionCategory.system
    let icon: NSImage? = nil
    
    // MARK: - Actions
    
    lazy var providedActions: [PluginAction] = [
        // Display brightness
        PluginAction(
            id: "brightness_up",
            name: "Brightness Up",
            description: "Increase display brightness",
            supportsRepeat: true,
            icon: "sun.max"
        ),
        PluginAction(
            id: "brightness_down",
            name: "Brightness Down",
            description: "Decrease display brightness",
            supportsRepeat: true,
            icon: "sun.min"
        ),
        
        // Keyboard brightness
        PluginAction(
            id: "keyboard_brightness_up",
            name: "Keyboard Brightness Up",
            description: "Increase keyboard brightness",
            supportsRepeat: true,
            icon: "keyboard.badge.ellipsis"
        ),
        PluginAction(
            id: "keyboard_brightness_down",
            name: "Keyboard Brightness Down",
            description: "Decrease keyboard brightness",
            supportsRepeat: true,
            icon: "keyboard"
        ),
        
        // System features
        PluginAction(
            id: "toggle_dark_mode",
            name: "Toggle Dark Mode",
            description: "Switch between light and dark mode",
            icon: "moon.circle"
        ),
        PluginAction(
            id: "toggle_do_not_disturb",
            name: "Toggle Do Not Disturb",
            description: "Enable/disable Do Not Disturb mode",
            icon: "moon.zzz"
        ),
        PluginAction(
            id: "toggle_night_shift",
            name: "Toggle Night Shift",
            description: "Enable/disable Night Shift",
            icon: "sunset"
        ),
        
        // Screenshots
        PluginAction(
            id: "screenshot_full",
            name: "Screenshot - Full Screen",
            description: "Take a screenshot of entire screen",
            icon: "camera"
        ),
        PluginAction(
            id: "screenshot_selection",
            name: "Screenshot - Selection",
            description: "Take a screenshot of selected area",
            icon: "camera.viewfinder"
        ),
        PluginAction(
            id: "screenshot_window",
            name: "Screenshot - Window",
            description: "Take a screenshot of a window",
            icon: "camera.on.rectangle"
        ),
        PluginAction(
            id: "screenshot_clipboard",
            name: "Screenshot to Clipboard",
            description: "Take screenshot to clipboard",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "type",
                    name: "Screenshot Type",
                    type: .selection,
                    defaultValue: AnyCodable("full"),
                    description: "Type of screenshot",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("full"),
                        AnyCodable("selection"),
                        AnyCodable("window")
                    ])
                )
            ],
            icon: "camera.fill"
        ),
        
        // Power management
        PluginAction(
            id: "system_sleep",
            name: "System Sleep",
            description: "Put computer to sleep",
            icon: "moon.zzz.fill"
        ),
        PluginAction(
            id: "restart",
            name: "Restart",
            description: "Restart the computer",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "confirm",
                    name: "Show Confirmation",
                    type: .boolean,
                    defaultValue: AnyCodable(true),
                    description: "Show confirmation dialog"
                )
            ],
            icon: "restart.circle"
        ),
        PluginAction(
            id: "shutdown",
            name: "Shutdown",
            description: "Shut down the computer",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "confirm",
                    name: "Show Confirmation",
                    type: .boolean,
                    defaultValue: AnyCodable(true),
                    description: "Show confirmation dialog"
                )
            ],
            icon: "power.circle"
        ),
        PluginAction(
            id: "logout",
            name: "Log Out",
            description: "Log out current user",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "confirm",
                    name: "Show Confirmation",
                    type: .boolean,
                    defaultValue: AnyCodable(true),
                    description: "Show confirmation dialog"
                )
            ],
            icon: "person.crop.circle.badge.xmark"
        )
    ]
    
    // MARK: - Plugin Lifecycle
    
    private var context: PluginContext?
    
    func initialize(context: PluginContext) throws {
        self.context = context
        context.logger.log("System Control Plugin initialized", file: #file, function: #function, line: #line)
    }
    
    func cleanup() {
        context?.logger.log("System Control Plugin cleaned up", file: #file, function: #function, line: #line)
        context = nil
    }
    
    // MARK: - Action Execution
    
    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        // Display brightness
        case "brightness_up":
            adjustBrightness(increase: true, context: context)
        case "brightness_down":
            adjustBrightness(increase: false, context: context)
            
        // Keyboard brightness
        case "keyboard_brightness_up":
            adjustKeyboardBrightness(increase: true, context: context)
        case "keyboard_brightness_down":
            adjustKeyboardBrightness(increase: false, context: context)
            
        // System features
        case "toggle_dark_mode":
            toggleDarkMode(context: context)
        case "toggle_do_not_disturb":
            toggleDoNotDisturb(context: context)
        case "toggle_night_shift":
            toggleNightShift(context: context)
            
        // Screenshots
        case "screenshot_full":
            takeScreenshot(type: .fullScreen, context: context)
        case "screenshot_selection":
            takeScreenshot(type: .selection, context: context)
        case "screenshot_window":
            takeScreenshot(type: .window, context: context)
        case "screenshot_clipboard":
            let type = parameters.string(for: "type") ?? "full"
            takeScreenshotToClipboard(type: ScreenshotType(rawValue: type) ?? .fullScreen, context: context)
            
        // Power management
        case "system_sleep":
            systemSleep(context: context)
        case "restart":
            let confirm = parameters.bool(for: "confirm") ?? true
            restart(showConfirmation: confirm, context: context)
        case "shutdown":
            let confirm = parameters.bool(for: "confirm") ?? true
            shutdown(showConfirmation: confirm, context: context)
        case "logout":
            let confirm = parameters.bool(for: "confirm") ?? true
            logOut(showConfirmation: confirm, context: context)
            
        default:
            throw PluginError.actionNotFound(action.id)
        }
    }
    
    func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        return .valid
    }
    
    func configurationView(for action: PluginAction) -> NSView? {
        return nil
    }
    
    // MARK: - Private Implementation
    
    private enum ScreenshotType: String {
        case fullScreen = "full"
        case selection = "selection"
        case window = "window"
    }
    
    private func adjustBrightness(increase: Bool, context: PluginContext) {
        // Brightness keys are F1/F2 
        let keyCode: CGKeyCode = increase ? 118 : 119 // F2/F1
        context.sendKeyboardShortcut(keyCode: keyCode, modifiers: [])
    }
    
    private func adjustKeyboardBrightness(increase: Bool, context: PluginContext) {
        // Keyboard brightness keys are F5/F6
        let keyCode: CGKeyCode = increase ? 96 : 97 // F5/F6
        context.sendKeyboardShortcut(keyCode: keyCode, modifiers: [])
    }
    
    private func toggleDarkMode(context: PluginContext) {
        let script = """
            tell application "System Events"
                tell appearance preferences
                    set dark mode to not dark mode
                end tell
            end tell
        """
        try? context.executeAppleScript(script)
    }
    
    private func toggleDoNotDisturb(context: PluginContext) {
        let script = """
            tell application "System Events"
                option key down
                click menu bar item 1 of menu bar 2 of application process "ControlCenter"
                option key up
            end tell
        """
        try? context.executeAppleScript(script)
    }
    
    private func toggleNightShift(context: PluginContext) {
        // Night Shift toggle would require more complex implementation
        // For now, just toggle dark mode as a placeholder
        toggleDarkMode(context: context)
    }
    
    private func takeScreenshot(type: ScreenshotType, context: PluginContext) {
        switch type {
        case .fullScreen:
            context.sendKeyboardShortcut(keyCode: 20, modifiers: [.maskCommand, .maskShift]) // Cmd+Shift+3
        case .selection:
            context.sendKeyboardShortcut(keyCode: 21, modifiers: [.maskCommand, .maskShift]) // Cmd+Shift+4
        case .window:
            context.sendKeyboardShortcut(keyCode: 21, modifiers: [.maskCommand, .maskShift]) // Cmd+Shift+4
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                context.sendKeyboardShortcut(keyCode: 49, modifiers: []) // Space
            }
        }
    }
    
    private func takeScreenshotToClipboard(type: ScreenshotType, context: PluginContext) {
        switch type {
        case .fullScreen:
            context.sendKeyboardShortcut(keyCode: 20, modifiers: [.maskCommand, .maskControl, .maskShift])
        case .selection:
            context.sendKeyboardShortcut(keyCode: 21, modifiers: [.maskCommand, .maskControl, .maskShift])
        case .window:
            context.sendKeyboardShortcut(keyCode: 21, modifiers: [.maskCommand, .maskControl, .maskShift])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                context.sendKeyboardShortcut(keyCode: 49, modifiers: [])
            }
        }
    }
    
    private func systemSleep(context: PluginContext) {
        let script = """
            tell application "System Events"
                sleep
            end tell
        """
        try? context.executeAppleScript(script)
    }
    
    /// Shared helper: optionally show a confirmation dialog, then run an AppleScript command.
    private func executeWithConfirmation(title: String, message: String, buttonTitle: String,
                                         showConfirmation: Bool, script: String, context: PluginContext) {
        let run = {
            try? context.executeAppleScript(script)
        }
        guard showConfirmation else { run(); return }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: buttonTitle)
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { run() }
        }
    }
    
    private func restart(showConfirmation: Bool, context: PluginContext) {
        executeWithConfirmation(title: "Restart Computer",
                               message: "Are you sure you want to restart your computer?",
                               buttonTitle: "Restart", showConfirmation: showConfirmation,
                               script: "tell application \"System Events\" to restart", context: context)
    }
    
    private func shutdown(showConfirmation: Bool, context: PluginContext) {
        executeWithConfirmation(title: "Shutdown Computer",
                               message: "Are you sure you want to shut down your computer?",
                               buttonTitle: "Shutdown", showConfirmation: showConfirmation,
                               script: "tell application \"System Events\" to shut down", context: context)
    }
    
    private func logOut(showConfirmation: Bool, context: PluginContext) {
        executeWithConfirmation(title: "Log Out",
                               message: "Are you sure you want to log out?",
                               buttonTitle: "Log Out", showConfirmation: showConfirmation,
                               script: "tell application \"System Events\" to log out", context: context)
    }
}
