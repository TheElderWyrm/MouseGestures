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
                        AnyCodable("down"),
                        AnyCodable("set")
                    ]),
                    displayValues: ["up": "Increase", "down": "Decrease", "set": "Set to Value"]
                ),
                ParameterDefinition(
                    key: "amount",
                    name: "Steps",
                    type: .number,
                    defaultValue: AnyCodable(1),
                    description: "Number of brightness steps",
                    validation: ValidationRule(minValue: 1, maxValue: 16),
                    visibleWhen: ParameterVisibilityRule(key: "direction", anyOf: ["up", "down"]),
                    suffix: "steps"
                ),
                ParameterDefinition(
                    key: "value",
                    name: "Brightness Level",
                    type: .number,
                    defaultValue: AnyCodable(50),
                    description: "Brightness percentage (0–100)",
                    validation: ValidationRule(minValue: 0, maxValue: 100),
                    visibleWhen: ParameterVisibilityRule(key: "direction", value: "set"),
                    suffix: "%"
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
                        AnyCodable("down"),
                        AnyCodable("set")
                    ]),
                    displayValues: ["up": "Increase", "down": "Decrease", "set": "Set to Value"]
                ),
                ParameterDefinition(
                    key: "amount",
                    name: "Steps",
                    type: .number,
                    defaultValue: AnyCodable(1),
                    description: "Number of brightness steps",
                    validation: ValidationRule(minValue: 1, maxValue: 16),
                    visibleWhen: ParameterVisibilityRule(key: "direction", anyOf: ["up", "down"]),
                    suffix: "steps"
                ),
                ParameterDefinition(
                    key: "value",
                    name: "Brightness Level",
                    type: .number,
                    defaultValue: AnyCodable(50),
                    description: "Brightness percentage (0–100)",
                    validation: ValidationRule(minValue: 0, maxValue: 100),
                    visibleWhen: ParameterVisibilityRule(key: "direction", value: "set"),
                    suffix: "%"
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
                    defaultValue: AnyCodable("interactive"),
                    description: "What to capture",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("interactive"),
                        AnyCodable("full"),
                        AnyCodable("selection"),
                        AnyCodable("window")
                    ]),
                    displayValues: [
                        "interactive": "Screenshot Mode",
                        "full": "Full Screen",
                        "selection": "Selection",
                        "window": "Window"
                    ]
                ),
                ParameterDefinition(
                    key: "destination",
                    name: "Destination",
                    type: .selection,
                    defaultValue: AnyCodable("clipboard"),
                    description: "Where to save the screenshot",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("clipboard"),
                        AnyCodable("file_default"),
                        AnyCodable("file_custom")
                    ]),
                    visibleWhen: ParameterVisibilityRule(key: "type", anyOf: ["full", "selection", "window"]),
                    displayValues: [
                        "clipboard": "Copy to Clipboard",
                        "file_default": "Save to Desktop",
                        "file_custom": "Save to Custom Folder"
                    ]
                ),
                ParameterDefinition(
                    key: "save_folder",
                    name: "Save Folder",
                    type: .path,
                    defaultValue: AnyCodable("~/Desktop"),
                    description: "Folder to save screenshots to",
                    visibleWhen: ParameterVisibilityRule(key: "destination", value: "file_custom")
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
        ),

        // MARK: Moved from Core
        PluginAction(
            id: "lock_screen",
            name: "Lock Screen",
            description: "Lock the screen",
            icon: "lock"
        ),
        PluginAction(
            id: "sleep_display",
            name: "Sleep Display",
            description: "Put the display(s) to sleep without sleeping the computer",
            icon: "moon"
        ),
        PluginAction(
            id: "empty_trash",
            name: "Empty Trash",
            description: "Empty the trash",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "confirm",
                    name: "Show Confirmation",
                    type: .boolean,
                    defaultValue: AnyCodable(true),
                    description: "Show confirmation dialog before emptying"
                )
            ],
            icon: "trash"
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
            if direction == "set" {
                let targetPct = parameters.number(for: "value") ?? 50
                setDisplayBrightness(Float(targetPct) / 100.0)
            } else {
                let steps = max(1, Int(parameters.number(for: "amount") ?? 1))
                for _ in 0..<steps { adjustBrightness(increase: direction == "up") }
            }

        // Consolidated keyboard brightness
        case "keyboard_brightness":
            let direction = parameters.string(for: "direction") ?? "up"
            if direction == "set" {
                let targetPct = parameters.number(for: "value") ?? 50
                setKeyboardBrightness(Float(targetPct) / 100.0)
            } else {
                let steps = max(1, Int(parameters.number(for: "amount") ?? 1))
                for _ in 0..<steps { adjustKeyboardBrightness(increase: direction == "up") }
            }

        // System features
        case "toggle_dark_mode":
            toggleDarkMode(context: context)
        case "toggle_do_not_disturb":
            toggleDoNotDisturb(context: context)

        // Consolidated screenshot
        case "screenshot":
            let type = parameters.string(for: "type") ?? "interactive"
            let destination = parameters.string(for: "destination") ?? "clipboard"
            let saveFolder = parameters.string(for: "save_folder")
            takeScreenshot(type: type, destination: destination, saveFolder: saveFolder, context: context)

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

        // MARK: Moved from Core
        case "lock_screen":
            lockScreen(context: context)
        case "sleep_display":
            sleepDisplay(context: context)
        case "empty_trash":
            let confirm = parameters.bool(for: "confirm") ?? true
            emptyTrash(showConfirmation: confirm, context: context)

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
        usleep(20_000)
    }

    // MARK: - Programmatic Brightness (NX key steps)

    private func setDisplayBrightness(_ level: Float) {
        let clamped = max(0, min(1, level))
        for _ in 0..<16 { sendNXKeyEvent(.brightnessDown); usleep(10_000) }
        let steps = Int((Double(clamped) * 16).rounded())
        for _ in 0..<steps { sendNXKeyEvent(.brightnessUp); usleep(10_000) }
    }

    private func setKeyboardBrightness(_ level: Float) {
        let clamped = max(0, min(1, level))
        for _ in 0..<16 { sendNXKeyEvent(.keyboardBrightDown); usleep(20_000) }
        let steps = Int((Double(clamped) * 16).rounded())
        for _ in 0..<steps { sendNXKeyEvent(.keyboardBrightUp); usleep(20_000) }
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
        // Primary: toggle via defaults + usernoted signal (works on macOS 12+)
        let script = """
            set dndState to do shell script "defaults -currentHost read com.apple.notificationcenterui doNotDisturb 2>/dev/null || echo 0"
            if dndState is "1" then
                do shell script "defaults -currentHost write com.apple.notificationcenterui doNotDisturb -bool false; killall usernoted 2>/dev/null; exit 0"
            else
                do shell script "defaults -currentHost write com.apple.notificationcenterui doNotDisturb -bool true; killall usernoted 2>/dev/null; exit 0"
            end if
        """
        do {
            try context.executeAppleScript(script)
            context.logger.log("Do Not Disturb toggled via defaults", file: #file, function: #function, line: #line)
        } catch {
            // Fallback: F6 key simulation
            context.logger.log("DND AppleScript failed (\(error.localizedDescription)), falling back to F6", file: #file, function: #function, line: #line)
            waitForModifierRelease()
            DispatchQueue.global(qos: .userInitiated).async {
                guard let source = CGEventSource(stateID: .privateState),
                      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 97, keyDown: true),
                      let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 97, keyDown: false) else { return }
                keyDown.flags = []
                keyUp.flags   = []
                keyDown.post(tap: .cghidEventTap)
                usleep(100_000)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Screenshots (consolidated)

    private func takeScreenshot(type: String, destination: String, saveFolder: String?, context: PluginContext) {
        if type == "interactive" {
            // Open the screenshot toolbar (same as Cmd+Shift+5)
            // Destination parameter is ignored — user chooses from the toolbar
            waitForModifierRelease()
            do {
                try context.executeAppleScript("""
                    tell application "System Events"
                        key code 23 using {command down, shift down}
                    end tell
                """)
            } catch {
                context.logger.log("Screenshot toolbar failed: \(error.localizedDescription)", file: #file, function: #function, line: #line)
            }
            return
        }

        // Use screencapture CLI for specific capture modes
        var args: [String] = []

        let toClipboard = (destination == "clipboard")

        if toClipboard {
            args.append("-c") // Copy to clipboard
        }

        switch type {
        case "full":
            break
        case "selection":
            args.append("-s") // Interactive selection
        case "window":
            args.append("-w") // Window capture (click to select)
        default:
            break
        }

        // Suppress the shutter sound
        args.append("-x")

        // When saving to file, generate a timestamped filename
        if !toClipboard {
            let folder: String
            if destination == "file_custom", let customFolder = saveFolder, !customFolder.isEmpty {
                folder = NSString(string: customFolder).expandingTildeInPath
            } else {
                folder = NSString(string: "~/Desktop").expandingTildeInPath
            }

            // Ensure the folder exists
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let timestamp = dateFormatter.string(from: Date())
            let filename = "Screenshot \(timestamp).png"
            let filePath = (folder as NSString).appendingPathComponent(filename)
            args.append(filePath)
        }

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

    // MARK: - Moved from Core

    private func lockScreen(context: PluginContext) {
        context.sendKeyboardShortcut(keyCode: 12, modifiers: [.maskCommand, .maskControl]) // Cmd+Ctrl+Q
    }

    private func sleepDisplay(context: PluginContext) {
        try? context.executeAppleScript("do shell script \"pmset displaysleepnow\"")
    }

    private func emptyTrash(showConfirmation: Bool, context: PluginContext) {
        // Use Finder via AppleScript. The "empty trash" command requires Finder
        // to be running (it always is).
        if showConfirmation {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Empty Trash"
                alert.informativeText = "Are you sure you want to permanently delete the items in the Trash?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Empty Trash")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                self.performEmptyTrash(context: context)
            }
        } else {
            performEmptyTrash(context: context)
        }
    }

    private func performEmptyTrash(context: PluginContext) {
        DispatchQueue.global(qos: .userInitiated).async {
            let previousApp = context.getFrontmostApplication()
            do {
                // Use Finder's AppleScript command with warning suppressed
                try context.executeAppleScript("""
                    tell application "Finder"
                        set warns before emptying of trash to false
                        empty trash
                        set warns before emptying of trash to true
                    end tell
                """)
                usleep(300_000)
                if let prev = previousApp {
                    DispatchQueue.main.async {
                        prev.activate(options: [])
                    }
                }
            } catch {
                context.logger.log("Failed to empty trash: \(error.localizedDescription)", file: #file, function: #function, line: #line)
            }
        }
    }
}
