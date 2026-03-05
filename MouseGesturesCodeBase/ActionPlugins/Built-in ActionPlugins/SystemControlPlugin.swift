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
            

        // Consolidated keyboard brightness
        case "keyboard_brightness":
            let direction = parameters.string(for: "direction") ?? "up"
            adjustKeyboardBrightness(increase: direction == "up")
            

        // System features
        case "toggle_dark_mode":
            toggleDarkMode(context: context)
        case "toggle_do_not_disturb":
            toggleDoNotDisturb(context: context)
        case "toggle_night_shift":
            toggleNightShift(context: context)
            
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
        // Toggle DND/Focus via Control Center UI scripting.
        // Uses multiple strategies to find the Focus item and DND toggle
        // across macOS versions (Ventura, Sonoma, Sequoia).
        waitForModifierRelease()
        DispatchQueue.global(qos: .userInitiated).async {
            let script = """
                tell application "System Events"
                    tell application process "ControlCenter"
                        -- Strategy 1: Find Focus menu bar item by name or description
                        set focusItem to missing value
                        repeat with mi in menu bar items of menu bar 1
                            try
                                set itemName to name of mi
                                set itemDesc to description of mi
                                if itemName is "Focus" or itemDesc contains "Focus" or itemDesc contains "Do Not Disturb" then
                                    set focusItem to mi
                                    exit repeat
                                end if
                            end try
                        end repeat
                        
                        if focusItem is missing value then
                            error "Could not find Focus menu bar item"
                        end if
                        
                        click focusItem
                        delay 0.5
                        
                        -- Find and click the Do Not Disturb toggle in the panel
                        set dndClicked to false
                        try
                            -- Try by name first (most reliable on Sonoma+)
                            tell window 1
                                repeat with cb in checkboxes of group 1
                                    try
                                        if title of cb contains "Do Not Disturb" or description of cb contains "Do Not Disturb" then
                                            click cb
                                            set dndClicked to true
                                            exit repeat
                                        end if
                                    end try
                                end repeat
                                -- Fallback: click first checkbox in group 1
                                if not dndClicked then
                                    click checkbox 1 of group 1
                                    set dndClicked to true
                                end if
                            end tell
                        on error
                            -- Last resort: try checkbox in any group
                            try
                                click checkbox 1 of group 1 of window 1
                            end try
                        end try
                        
                        delay 0.15
                        key code 53 -- Escape to close panel
                    end tell
                end tell
            """
            do {
                try context.executeAppleScript(script)
                context.logger.log("Do Not Disturb toggled via Control Center", file: #file, function: #function, line: #line)
            } catch {
                context.logger.log("DND toggle failed: \(error.localizedDescription)", file: #file, function: #function, line: #line)
            }
        }
    }
    
    private func toggleNightShift(context: PluginContext) {
        // Use the private CoreBrightness framework via ObjC runtime to toggle Night Shift.
        // CBBlueLightClient provides the Night Shift API on macOS.
        DispatchQueue.global(qos: .userInitiated).async {
            // Load the private CoreBrightness framework
            let frameworkPath = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            guard dlopen(frameworkPath, RTLD_NOW) != nil else {
                context.logger.log("Failed to load CoreBrightness framework", file: #file, function: #function, line: #line)
                return
            }
            
            // Get the CBBlueLightClient class
            guard let clientClass = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
                context.logger.log("CBBlueLightClient class not found", file: #file, function: #function, line: #line)
                return
            }
            
            let client = clientClass.init()
            
            let getStatusSel = NSSelectorFromString("getBlueLightStatus:")
            let setEnabledSel = NSSelectorFromString("setEnabled:")
            
            guard client.responds(to: getStatusSel),
                  client.responds(to: setEnabledSel) else {
                context.logger.log("CBBlueLightClient missing expected methods", file: #file, function: #function, line: #line)
                return
            }
            
            // CBBlueLightStatus struct layout (from reverse engineering):
            //   offset 0: Bool available    (1 byte)
            //   offset 1: Bool enabled      (1 byte)
            //   offset 2: Bool sunSchedulePermitted (1 byte)
            //   offset 4: Int32 mode        (4 bytes, after padding)
            //   ... schedule data follows
            var statusBuffer = [UInt8](repeating: 0, count: 512)
            
            let imp = client.method(for: getStatusSel)
            typealias GetStatusFunc = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
            let getStatus = unsafeBitCast(imp, to: GetStatusFunc.self)
            let success = getStatus(client, getStatusSel, &statusBuffer)
            
            guard success else {
                context.logger.log("getBlueLightStatus: returned false", file: #file, function: #function, line: #line)
                return
            }
            
            let available = statusBuffer[0] != 0
            let enabled = statusBuffer[1] != 0
            
            guard available else {
                context.logger.log("Night Shift not available on this display", file: #file, function: #function, line: #line)
                return
            }
            
            context.logger.log("Night Shift currently \(enabled ? "on" : "off"), toggling...", file: #file, function: #function, line: #line)
            
            // Toggle: call setEnabled: with the opposite value
            let setImp = client.method(for: setEnabledSel)
            typealias SetEnabledFunc = @convention(c) (AnyObject, Selector, Bool) -> Bool
            let setEnabled = unsafeBitCast(setImp, to: SetEnabledFunc.self)
            let result = setEnabled(client, setEnabledSel, !enabled)
            
            if result {
                context.logger.log("Night Shift toggled \(!enabled ? "on" : "off")", file: #file, function: #function, line: #line)
            } else {
                // setEnabled: may return false even on success (void return cast)
                // Verify by re-reading status
                var verifyBuffer = [UInt8](repeating: 0, count: 512)
                let verifySuccess = getStatus(client, getStatusSel, &verifyBuffer)
                if verifySuccess && (verifyBuffer[1] != 0) != enabled {
                    context.logger.log("Night Shift toggled \(!enabled ? "on" : "off") (verified)", file: #file, function: #function, line: #line)
                } else {
                    context.logger.log("Night Shift toggle may have failed", file: #file, function: #function, line: #line)
                }
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
}
