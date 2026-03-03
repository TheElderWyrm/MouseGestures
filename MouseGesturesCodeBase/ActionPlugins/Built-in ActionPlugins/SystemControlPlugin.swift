import Cocoa

// MARK: - System Control Plugin

/// Built-in plugin for system control actions
class SystemControlPlugin: NSObject, GestureActionPlugin {
    
    // MARK: - Plugin Properties
    
    let identifier = "com.mousegestures.system"
    let name = "System Control"
    override var description: String { "Control system settings and display" }
    let version = "2.0.0"
    let author = "MouseGestures"
    let category = ActionCategory.system
    let icon: NSImage? = nil
    
    // MARK: - NX Media Key Types for Brightness
    
    /// System media key types (from IOKit/hidsystem)
    private enum NXKeyType: UInt32 {
        case brightnessUp       = 2   // NX_KEYTYPE_BRIGHTNESS_UP
        case brightnessDown     = 3   // NX_KEYTYPE_BRIGHTNESS_DOWN
        case keyboardBrightUp   = 21  // NX_KEYTYPE_ILLUMINATION_UP
        case keyboardBrightDown = 22  // NX_KEYTYPE_ILLUMINATION_DOWN
    }
    
    // MARK: - Actions
    
    lazy var providedActions: [PluginAction] = [
        // Consolidated: brightness_up + brightness_down → display_brightness
        PluginAction(
            id: "display_brightness",
            name: "Display Brightness",
            description: "Adjust display brightness",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "direction",
                    name: "Direction",
                    type: .selection,
                    defaultValue: AnyCodable("up"),
                    description: "Increase or decrease brightness",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("up"),
                        AnyCodable("down")
                    ]),
                    displayValues: ["up": "Increase", "down": "Decrease"]
                )
            ],
            supportsRepeat: true,
            icon: "sun.max"
        ),
        
        // Consolidated: keyboard_brightness_up + keyboard_brightness_down → keyboard_brightness
        PluginAction(
            id: "keyboard_brightness",
            name: "Keyboard Brightness",
            description: "Adjust keyboard backlight brightness",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "direction",
                    name: "Direction",
                    type: .selection,
                    defaultValue: AnyCodable("up"),
                    description: "Increase or decrease keyboard brightness",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("up"),
                        AnyCodable("down")
                    ]),
                    displayValues: ["up": "Increase", "down": "Decrease"]
                )
            ],
            supportsRepeat: true,
            icon: "keyboard.badge.ellipsis"
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
        
        // Consolidated: all screenshot actions → screenshot
        PluginAction(
            id: "screenshot",
            name: "Screenshot",
            description: "Take a screenshot",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "type",
                    name: "Capture Type",
                    type: .selection,
                    defaultValue: AnyCodable("full"),
                    description: "What to capture",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("full"),
                        AnyCodable("selection"),
                        AnyCodable("window"),
                        AnyCodable("interactive")
                    ]),
                    displayValues: [
                        "full": "Full Screen",
                        "selection": "Selection",
                        "window": "Window",
                        "interactive": "Screenshot Mode"
                    ]
                ),
                ParameterDefinition(
                    key: "destination",
                    name: "Destination",
                    type: .selection,
                    defaultValue: AnyCodable("file"),
                    description: "Where to save the screenshot",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("file"),
                        AnyCodable("clipboard")
                    ]),
                    displayValues: ["file": "Save to File", "clipboard": "Copy to Clipboard"]
                )
            ],
            icon: "camera"
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
        // Consolidated display brightness
        case "display_brightness":
            let direction = parameters.string(for: "direction") ?? "up"
            adjustBrightness(increase: direction == "up")
            
        // Legacy aliases for backward compatibility
        case "brightness_up":
            adjustBrightness(increase: true)
        case "brightness_down":
            adjustBrightness(increase: false)
            
        // Consolidated keyboard brightness
        case "keyboard_brightness":
            let direction = parameters.string(for: "direction") ?? "up"
            adjustKeyboardBrightness(increase: direction == "up")
            
        // Legacy aliases
        case "keyboard_brightness_up":
            adjustKeyboardBrightness(increase: true)
        case "keyboard_brightness_down":
            adjustKeyboardBrightness(increase: false)
            
        // System features
        case "toggle_dark_mode":
            toggleDarkMode(context: context)
        case "toggle_do_not_disturb":
            toggleDoNotDisturb(context: context)
        case "toggle_night_shift":
            toggleNightShift(context: context)
            
        // Consolidated screenshot
        case "screenshot":
            let type = parameters.string(for: "type") ?? "full"
            let destination = parameters.string(for: "destination") ?? "file"
            takeScreenshot(type: type, toClipboard: destination == "clipboard", context: context)
            
        // Legacy aliases
        case "screenshot_full":
            takeScreenshot(type: "full", toClipboard: false, context: context)
        case "screenshot_selection":
            takeScreenshot(type: "selection", toClipboard: false, context: context)
        case "screenshot_window":
            takeScreenshot(type: "window", toClipboard: false, context: context)
        case "screenshot_clipboard":
            let type = parameters.string(for: "type") ?? "full"
            takeScreenshot(type: type, toClipboard: true, context: context)
            
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
    
    // MARK: - NX Media Key Sending
    
    /// Send a system NX key event (used for brightness keys that the OS intercepts).
    /// This uses the same mechanism as physical keyboard brightness keys.
    private func sendNXKeyEvent(_ key: NXKeyType) {
        // Key down: key type in bits 16-23, state 0x0A (down) in bits 8-15
        let keyDownData = Int((key.rawValue << 16) | (0x0A << 8))
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            data1: keyDownData,
            data2: -1
        )
        
        // Key up: state 0x0B (up) in bits 8-15
        let keyUpData = Int((key.rawValue << 16) | (0x0B << 8))
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: keyUpData,
            data2: -1
        )
        
        if let keyDown = keyDown {
            keyDown.cgEvent?.post(tap: .cghidEventTap)
        }
        if let keyUp = keyUp {
            keyUp.cgEvent?.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Brightness (fixed: now uses NX media keys)
    
    private func adjustBrightness(increase: Bool) {
        sendNXKeyEvent(increase ? .brightnessUp : .brightnessDown)
    }
    
    private func adjustKeyboardBrightness(increase: Bool) {
        sendNXKeyEvent(increase ? .keyboardBrightUp : .keyboardBrightDown)
    }
    
    // MARK: - System Features
    
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
        // Use the shortcuts CLI to toggle Focus/DND — more reliable than UI scripting
        // which caused modifier key interference and stuck option keys.
        // Falls back to defaults-based approach if shortcuts unavailable.
        DispatchQueue.global(qos: .userInitiated).async {
            // Primary approach: use defaults to toggle DND assertion
            // On macOS Monterey+, DND state is stored in com.apple.controlcenter
            let checkScript = """
                do shell script "defaults -currentHost read com.apple.notificationcenterui doNotDisturb 2>/dev/null || echo 0"
            """
            var error: NSDictionary?
            if let scriptObj = NSAppleScript(source: checkScript) {
                let result = scriptObj.executeAndReturnError(&error)
                let currentState = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                let newState = currentState ? "false" : "true"
                
                let toggleScript = """
                    do shell script "defaults -currentHost write com.apple.notificationcenterui doNotDisturb -boolean \(newState)"
                    do shell script "defaults -currentHost write com.apple.notificationcenterui doNotDisturbDate -date '" & (current date) & "'"
                    do shell script "killall NotificationCenter 2>/dev/null || true; killall ControlCenter 2>/dev/null || true"
                """
                if let toggleObj = NSAppleScript(source: toggleScript) {
                    toggleObj.executeAndReturnError(&error)
                }
            }
        }
    }
    
    private func toggleNightShift(context: PluginContext) {
        // Use the private CoreBrightness framework via python3+pyobjc bridge.
        // CBBlueLightClient is the actual Night Shift API on macOS.
        // Build the python script as a single-line shell argument to avoid
        // Swift multi-line string indentation issues with embedded Python.
        let pythonCode = [
            "import ctypes, objc",
            "ctypes.cdll.LoadLibrary('/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness')",
            "objc.loadBundle('CoreBrightness', bundle_path='/System/Library/PrivateFrameworks/CoreBrightness.framework', module_globals=globals())",
            "c=CBBlueLightClient.alloc().init()",
            "s=c.getBlueLightStatus_(None)",
            "c.setEnabled_(not s[1].enabled() if s else True)"
        ].joined(separator: "; ")
        
        let script = "do shell script \"python3 -c '\(pythonCode)' 2>/dev/null\""
        
        // Fallback: open Night Shift pane in System Settings
        let fallbackScript = "do shell script \"open 'x-apple.systempreferences:com.apple.preference.displays?nightShift'\""
        
        do {
            try context.executeAppleScript(script)
        } catch {
            // If the python approach fails, try the fallback
            try? context.executeAppleScript(fallbackScript)
            context.logger.log("Night Shift toggle fell back to System Preferences", file: #file, function: #function, line: #line)
        }
    }
    
    // MARK: - Screenshots (consolidated)
    
    private func takeScreenshot(type: String, toClipboard: Bool, context: PluginContext) {
        // Use screencapture CLI for reliability — it handles all modes natively
        var args: [String] = []
        
        if toClipboard {
            args.append("-c") // Copy to clipboard
        }
        
        switch type {
        case "full":
            // No additional flags needed for full screen
            break
        case "selection":
            args.append("-s") // Interactive selection
        case "window":
            args.append("-w") // Window capture (click to select)
        case "interactive":
            args.append("-i") // Interactive mode (screenshot toolbar)
        default:
            break
        }
        
        // If saving to file (not clipboard), screencapture saves to desktop by default
        // Using -x to suppress the shutter sound
        args.append("-x")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = args
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                context.logger.log("Screenshot failed: \(error.localizedDescription)", file: #file, function: #function, line: #line)
            }
        }
    }
    
    // MARK: - Power Management
    
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
