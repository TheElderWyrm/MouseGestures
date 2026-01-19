import Cocoa
import Carbon

// MARK: - Automation Plugin  

/// Built-in plugin for automation actions like scripts and shortcuts
class AutomationPlugin: NSObject, GestureActionPlugin {
    
    // MARK: - Plugin Properties
    
    let identifier = "com.mousegestures.automation"
    let name = "Automation"
    override var description: String { "Run scripts, shortcuts, and automate tasks" }
    let version = "1.0.0"
    let author = "MouseGestures"
    let category = ActionCategory.automation
    let icon: NSImage? = nil
    
    // MARK: - Actions
    
    lazy var providedActions: [PluginAction] = [
        PluginAction(
            id: "keyboard_shortcut",
            name: "Keyboard Shortcut",
            description: "Trigger a keyboard shortcut",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "shortcut",
                    name: "Shortcut",
                    type: .keyboardShortcut,
                    required: true,
                    description: "The keyboard shortcut to trigger"
                )
            ],
            icon: "keyboard"
        ),
        PluginAction(
            id: "run_shortcut",
            name: "Run Shortcut",
            description: "Run a Shortcuts app shortcut",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "shortcut_name",
                    name: "Shortcut Name",
                    type: .string,
                    required: true,
                    description: "Name of the shortcut to run"
                ),
                ParameterDefinition(
                    key: "input",
                    name: "Input",
                    type: .string,
                    description: "Optional input to pass to the shortcut"
                )
            ],
            icon: "square.stack.3d.up"
        ),
        PluginAction(
            id: "run_script",
            name: "Run Script",
            description: "Execute a script",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "script_type",
                    name: "Script Type",
                    type: .selection,
                    required: true,
                    defaultValue: AnyCodable("applescript"),
                    description: "Type of script",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("applescript"),
                        AnyCodable("shell"),
                        AnyCodable("javascript"),
                        AnyCodable("python")
                    ])
                ),
                ParameterDefinition(
                    key: "script_content",
                    name: "Script",
                    type: .script,
                    description: "Script content"
                ),
                ParameterDefinition(
                    key: "script_path",
                    name: "Script Path",
                    type: .path,
                    description: "Path to script file"
                ),
                ParameterDefinition(
                    key: "use_file",
                    name: "Use File",
                    type: .boolean,
                    defaultValue: AnyCodable(false),
                    description: "Whether to use script file instead of content"
                )
            ],
            icon: "doc.text"
        ),
        PluginAction(
            id: "open_app",
            name: "Open Application",
            description: "Launch an application",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "app_identifier",
                    name: "Application",
                    type: .application,
                    required: true,
                    description: "Application to launch"
                ),
                ParameterDefinition(
                    key: "bring_to_front",
                    name: "Bring to Front",
                    type: .boolean,
                    defaultValue: AnyCodable(true),
                    description: "Bring app to front if already running"
                )
            ],
            icon: "app"
        ),
        PluginAction(
            id: "open_file",
            name: "Open File",
            description: "Open a file or folder",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "file_path",
                    name: "File Path",
                    type: .path,
                    required: true,
                    description: "Path to file or folder"
                ),
                ParameterDefinition(
                    key: "open_with",
                    name: "Open With",
                    type: .application,
                    description: "Application to open file with"
                )
            ],
            icon: "folder"
        ),
        PluginAction(
            id: "open_url",
            name: "Open URL",
            description: "Open a URL in default browser",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "url",
                    name: "URL",
                    type: .url,
                    required: true,
                    description: "URL to open"
                ),
                ParameterDefinition(
                    key: "browser",
                    name: "Browser",
                    type: .application,
                    description: "Specific browser to use"
                )
            ],
            icon: "safari"
        ),
        PluginAction(
            id: "search_finder",
            name: "Search in Finder",
            description: "Search for files in Finder",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "query",
                    name: "Search Query",
                    type: .string,
                    required: true,
                    description: "What to search for"
                ),
                ParameterDefinition(
                    key: "scope",
                    name: "Search Scope",
                    type: .selection,
                    defaultValue: AnyCodable("current"),
                    description: "Where to search",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("current"),
                        AnyCodable("home"),
                        AnyCodable("entire_mac"),
                        AnyCodable("custom")
                    ])
                ),
                ParameterDefinition(
                    key: "custom_path",
                    name: "Custom Path",
                    type: .path,
                    description: "Path when using custom scope"
                )
            ],
            icon: "magnifyingglass"
        ),
        PluginAction(
            id: "bundle_actions",
            name: "Bundle Actions",
            description: "Execute multiple actions in sequence",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "actions",
                    name: "Actions",
                    type: .json,
                    required: true,
                    description: "List of actions to execute"
                ),
                ParameterDefinition(
                    key: "delay_between",
                    name: "Delay Between Actions",
                    type: .number,
                    defaultValue: AnyCodable(0.2),
                    description: "Seconds to wait between actions",
                    validation: ValidationRule(minValue: 0, maxValue: 10)
                )
            ],
            icon: "square.stack"
        ),
        PluginAction(
            id: "clipboard_action",
            name: "Clipboard Action",
            description: "Manipulate clipboard contents",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "action",
                    name: "Action",
                    type: .selection,
                    required: true,
                    defaultValue: AnyCodable("copy"),
                    description: "Clipboard action to perform",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("copy"),
                        AnyCodable("paste"),
                        AnyCodable("cut"),
                        AnyCodable("clear"),
                        AnyCodable("set_text")
                    ])
                ),
                ParameterDefinition(
                    key: "text",
                    name: "Text",
                    type: .string,
                    description: "Text to set (for set_text action)"
                )
            ],
            icon: "doc.on.clipboard"
        )
    ]
    
    // MARK: - Plugin Lifecycle
    
    func initialize(context: PluginContext) throws {
        context.logger.log("Automation Plugin initialized", file: #file, function: #function, line: #line)
    }
    
    func cleanup() {
        // Clean up any resources if needed
    }
    
    // MARK: - Action Execution
    
    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        guard ActionDebounce.shared.shouldExecute(action: "\(identifier).\(action.id)") else {
            context.logger.log("Action debounced: \(action.name)", file: #file, function: #function, line: #line)
            return
        }
        
        switch action.id {
        case "keyboard_shortcut":
            if let shortcutData = parameters.dictionary(for: "shortcut"),
               let shortcut = parseKeyboardShortcut(from: shortcutData) {
                executeKeyboardShortcut(shortcut)
            }
            
        case "run_shortcut":
            if let name = parameters.string(for: "shortcut_name") {
                let input = parameters.string(for: "input")
                runShortcut(name: name, input: input)
            }
            
        case "run_script":
            let scriptType = parameters.string(for: "script_type") ?? "applescript"
            let useFile = parameters.bool(for: "use_file") ?? false
            
            if useFile {
                if let path = parameters.string(for: "script_path") {
                    runScriptFile(at: path, type: scriptType, context: context)
                }
            } else {
                if let content = parameters.string(for: "script_content") {
                    runScriptContent(content, type: scriptType, context: context)
                }
            }
            
        case "open_app":
            if let appId = parameters.string(for: "app_identifier") {
                let bringToFront = parameters.bool(for: "bring_to_front") ?? true
                openApplication(identifier: appId, bringToFront: bringToFront, context: context)
            }
            
        case "open_file":
            if let path = parameters.string(for: "file_path") {
                let openWith = parameters.string(for: "open_with")
                openFile(at: path, with: openWith, context: context)
            }
            
        case "open_url":
            if let urlString = parameters.string(for: "url") {
                let browser = parameters.string(for: "browser")
                openURL(urlString, with: browser, context: context)
            }
            
        case "search_finder":
            if let query = parameters.string(for: "query") {
                let scope = parameters.string(for: "scope") ?? "current"
                let customPath = parameters.string(for: "custom_path")
                searchInFinder(query: query, scope: scope, customPath: customPath)
            }
            
        case "bundle_actions":
            if let actionsData = parameters.array(for: "actions") {
                let delay = parameters.number(for: "delay_between") ?? 0.2
                executeBundledActions(actionsData, delayBetween: delay, context: context)
            }
            
        case "clipboard_action":
            if let action = parameters.string(for: "action") {
                let text = parameters.string(for: "text")
                executeClipboardAction(action, text: text)
            }
            
        default:
            throw PluginError.actionNotFound(action.id)
        }
    }
    
    func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        switch action.id {
        case "keyboard_shortcut":
            guard parameters.dictionary(for: "shortcut") != nil else {
                return ValidationResult.invalid(error: "Keyboard shortcut is required")
            }
            
        case "run_shortcut":
            guard parameters.string(for: "shortcut_name") != nil else {
                return ValidationResult.invalid(error: "Shortcut name is required")
            }
            
        case "run_script":
            let useFile = parameters.bool(for: "use_file") ?? false
            if useFile {
                guard parameters.string(for: "script_path") != nil else {
                    return ValidationResult.invalid(error: "Script path is required when using file")
                }
            } else {
                guard parameters.string(for: "script_content") != nil else {
                    return ValidationResult.invalid(error: "Script content is required")
                }
            }
            
        case "open_app":
            guard parameters.string(for: "app_identifier") != nil else {
                return ValidationResult.invalid(error: "Application identifier is required")
            }
            
        case "open_file":
            guard parameters.string(for: "file_path") != nil else {
                return ValidationResult.invalid(error: "File path is required")
            }
            
        case "open_url":
            guard parameters.string(for: "url") != nil else {
                return ValidationResult.invalid(error: "URL is required")
            }
            
        case "search_finder":
            guard parameters.string(for: "query") != nil else {
                return ValidationResult.invalid(error: "Search query is required")
            }
            
        case "bundle_actions":
            guard parameters.array(for: "actions") != nil else {
                return ValidationResult.invalid(error: "Actions list is required")
            }
            
        case "app_intent":
            guard parameters.string(for: "app_bundle_id") != nil else {
                return ValidationResult.invalid(error: "Application bundle ID is required")
            }
            guard parameters.string(for: "intent_id") != nil else {
                return ValidationResult.invalid(error: "Intent ID is required")
            }
            
        case "clipboard_action":
            guard let action = parameters.string(for: "action") else {
                return ValidationResult.invalid(error: "Clipboard action is required")
            }
            if action == "set_text" && parameters.string(for: "text") == nil {
                return ValidationResult.invalid(error: "Text is required for set_text action")
            }
            
        default:
            break
        }
        
        return .valid
    }
    
    func configurationView(for action: PluginAction) -> NSView? {
        switch action.id {
        case "run_script":
            return createScriptConfigurationView()
        case "keyboard_shortcut":
            return createKeyboardShortcutConfigurationView()
        case "bundle_actions":
            return createBundleActionsConfigurationView()
        default:
            return createDefaultConfigurationView(for: action)
        }
    }
    
    // MARK: - Private Implementation
    
    private func parseKeyboardShortcut(from data: [String: Any]) -> KeyboardShortcut? {
        guard let keyCode = data["keyCode"] as? UInt16,
              let modifiers = data["modifiers"] as? UInt else {
            return nil
        }
        
        // Generate display string from the parsed data
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        
        // Simple key code to string mapping for display
        let keyStr: String
        switch keyCode {
        case 0: keyStr = "A"
        case 1: keyStr = "S"
        case 2: keyStr = "D"
        case 3: keyStr = "F"
        case 8: keyStr = "C"
        case 9: keyStr = "V"
        case 7: keyStr = "X"
        case 36: keyStr = "Return"
        case 49: keyStr = "Space"
        default: keyStr = "Key\(keyCode)"
        }
        parts.append(keyStr)
        
        let displayString = parts.joined()
        
        return KeyboardShortcut(
            keyCode: keyCode,
            modifiers: flags,
            displayString: displayString
        )
    }
    
    private func executeKeyboardShortcut(_ shortcut: KeyboardShortcut) {
        releaseAllModifiers()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
            
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else {
                return
            }
            
            keyDown.flags = shortcut.modifiers
            keyUp.flags = shortcut.modifiers
            
            keyDown.post(tap: .cghidEventTap)
            usleep(100000)
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    private func runShortcut(name: String, input: String?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            
            var args = ["run", name]
            if let input = input {
                args.append("--input-text")
                args.append(input)
            }
            process.arguments = args
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus != 0 {
                    // Fallback to AppleScript
                    self.runShortcutViaAppleScript(name: name)
                }
            } catch {
                self.runShortcutViaAppleScript(name: name)
            }
        }
    }
    
    private func runShortcutViaAppleScript(name: String) {
        let script = """
            tell application "Shortcuts Events"
                run shortcut "\(name.replacingOccurrences(of: "\"", with: "\\\\\""))"
            end tell
        """
        
        executeAppleScript(script)
    }
    
    private func runScriptContent(_ content: String, type: String, context: PluginContext) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            
            switch type {
            case "shell":
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", content]
                
            case "applescript":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", content]
                
            case "javascript":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-l", "JavaScript", "-e", content]
                
            case "python":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.arguments = ["-c", content]
                
            default:
                return
            }
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
            context.logger.log("Error executing script: \(error)", file: #file, function: #function, line: #line)
            }
        }
    }
    
    private func runScriptFile(at path: String, type: String, context: PluginContext) {
        guard FileManager.default.fileExists(atPath: path) else {
            context.logger.log("Script file not found: \(path)", file: #file, function: #function, line: #line)
            return
        }
        
        do {
            let content = try String(contentsOfFile: path)
            runScriptContent(content, type: type, context: context)
        } catch {
            context.logger.log("Error reading script file: \(error)", file: #file, function: #function, line: #line)
        }
    }
    
    private func openApplication(identifier: String, bringToFront: Bool, context: PluginContext) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = bringToFront
            
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    context.logger.log("Error opening application: \(error)", file: #file, function: #function, line: #line)
                }
            }
        } else {
            // Try as path
            let appURL = URL(fileURLWithPath: identifier)
            if FileManager.default.fileExists(atPath: appURL.path) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = bringToFront
                
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { (app, error) in
                    if let error = error {
                        context.logger.log("Error opening application: \(error)", file: #file, function: #function, line: #line)
                    }
                }
            }
        }
    }
    
    private func openFile(at path: String, with app: String?, context: PluginContext) {
        let fileURL = URL(fileURLWithPath: path)
        
        guard FileManager.default.fileExists(atPath: path) else {
            context.logger.log("File does not exist: \(path)", file: #file, function: #function, line: #line)
            return
        }
        
        if let app = app,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(fileURL)
        }
    }
    
    private func openURL(_ urlString: String, with browser: String?, context: PluginContext) {
        guard let url = URL(string: urlString) else {
            context.logger.log("Invalid URL: \(urlString)", file: #file, function: #function, line: #line)
            return
        }
        
        if let browser = browser,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func searchInFinder(query: String, scope: String, customPath: String?) {
        var searchPath: String
        
        switch scope {
        case "current":
            // Get current Finder window path
            let script = """
                tell application "Finder"
                    if exists window 1 then
                        return POSIX path of (target of window 1 as alias)
                    else
                        return POSIX path of (path to home folder)
                    end if
                end tell
            """
            
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let output = scriptObject.executeAndReturnError(&error)
                searchPath = output.stringValue ?? NSHomeDirectory()
            } else {
                searchPath = NSHomeDirectory()
            }
            
        case "home":
            searchPath = NSHomeDirectory()
            
        case "entire_mac":
            searchPath = "/"
            
        case "custom":
            searchPath = customPath ?? NSHomeDirectory()
            
        default:
            searchPath = NSHomeDirectory()
        }
        
        let escapedQuery = query.replacingOccurrences(of: "\"", with: "\\\\\"")
        let escapedPath = searchPath.replacingOccurrences(of: "'", with: "'\\''")
        
        let script = """
            tell application "Finder"
                activate
                set newWindow to make new Finder window
                set target of newWindow to POSIX file "\(escapedPath)"
                
                tell application "System Events"
                    tell process "Finder"
                        keystroke "f" using command down
                        delay 0.5
                        keystroke "\(escapedQuery)"
                    end tell
                end tell
            end tell
        """
        
        executeAppleScript(script)
    }
    
    private func executeBundledActions(_ actionsData: [Any], delayBetween: Double, context: PluginContext) {
        DispatchQueue.global(qos: .userInitiated).async {
            for (index, actionData) in actionsData.enumerated() {
                guard let action = actionData as? [String: Any],
                      let pluginId = action["plugin"] as? String,
                      let actionId = action["action"] as? String else {
                    continue
                }
                
                let parameters = ActionParameters(values: (action["parameters"] as? [String: AnyCodable]) ?? [:])
                let fullActionId = "\(pluginId).\(actionId)"
                
                do {
                    try PluginManager.shared.executeAction(identifier: fullActionId, parameters: parameters)
                } catch {
                    context.logger.log("Error executing bundled action: \(error)", file: #file, function: #function, line: #line)
                }
                
                if index < actionsData.count - 1 && delayBetween > 0 {
                    Thread.sleep(forTimeInterval: delayBetween)
                }
            }
        }
    }
    
    private func executeClipboardAction(_ action: String, text: String?) {
        switch action {
        case "copy":
            sendKeyboardShortcut(keyCode: 8, modifiers: [.maskCommand]) // Cmd+C
            
        case "paste":
            sendKeyboardShortcut(keyCode: 9, modifiers: [.maskCommand]) // Cmd+V
            
        case "cut":
            sendKeyboardShortcut(keyCode: 7, modifiers: [.maskCommand]) // Cmd+X
            
        case "clear":
            NSPasteboard.general.clearContents()
            
        case "set_text":
            if let text = text {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
            
        default:
            break
        }
    }
    
    private func releaseAllModifiers() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        
        let modifierKeys: [(CGKeyCode, CGKeyCode)] = [
            (0x37, 0x36), // Command L/R
            (0x3B, 0x3E), // Control L/R
            (0x3A, 0x3D), // Option L/R
            (0x38, 0x3C)  // Shift L/R
        ]
        
        for (left, right) in modifierKeys {
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: left, keyDown: false) {
                keyUp.flags = []
                keyUp.post(tap: .cghidEventTap)
            }
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: right, keyDown: false) {
                keyUp.flags = []
                keyUp.post(tap: .cghidEventTap)
            }
        }
        
        usleep(10000)
    }
    
    private func sendKeyboardShortcut(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        releaseAllModifiers()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
            
            keyDown.flags = modifiers
            keyUp.flags = modifiers
            
            keyDown.post(tap: .cghidEventTap)
            usleep(50000)
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    private func executeAppleScript(_ script: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
            }
        }
    }
    
    // MARK: - Configuration Views
    
    private func createScriptConfigurationView() -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        
        // Script Type Selector
        let typeLabel = NSTextField(labelWithString: "Script Type:")
        typeLabel.frame = NSRect(x: 20, y: 460, width: 100, height: 20)
        containerView.addSubview(typeLabel)
        
        let typePopup = NSPopUpButton(frame: NSRect(x: 130, y: 455, width: 200, height: 25))
        typePopup.removeAllItems()
        typePopup.addItems(withTitles: ["AppleScript", "Shell Script", "JavaScript", "Python"])
        typePopup.identifier = NSUserInterfaceItemIdentifier("script_type")
        containerView.addSubview(typePopup)
        
        // Source Selection
        let sourceLabel = NSTextField(labelWithString: "Source:")
        sourceLabel.frame = NSRect(x: 20, y: 420, width: 100, height: 20)
        containerView.addSubview(sourceLabel)
        
        let sourceSegmented = NSSegmentedControl(labels: ["Inline Script", "External File"], trackingMode: .selectOne, target: nil, action: nil)
        sourceSegmented.frame = NSRect(x: 130, y: 415, width: 200, height: 25)
        sourceSegmented.selectedSegment = 0
        sourceSegmented.identifier = NSUserInterfaceItemIdentifier("use_file")
        containerView.addSubview(sourceSegmented)
        
        // Script Path Field (for external files)
        let pathLabel = NSTextField(labelWithString: "Script Path:")
        pathLabel.frame = NSRect(x: 20, y: 380, width: 100, height: 20)
        pathLabel.identifier = NSUserInterfaceItemIdentifier("path_label")
        pathLabel.isHidden = true
        containerView.addSubview(pathLabel)
        
        let pathField = NSTextField(frame: NSRect(x: 130, y: 375, width: 350, height: 25))
        pathField.placeholderString = "/path/to/script.sh"
        pathField.identifier = NSUserInterfaceItemIdentifier("script_path")
        pathField.isHidden = true
        containerView.addSubview(pathField)
        
        let browseButton = NSButton(frame: NSRect(x: 490, y: 375, width: 90, height: 25))
        browseButton.bezelStyle = .rounded
        browseButton.title = "Browse..."
        browseButton.identifier = NSUserInterfaceItemIdentifier("browse_button")
        browseButton.isHidden = true
        browseButton.target = self
        browseButton.action = #selector(browseForScriptFile(_:))
        containerView.addSubview(browseButton)
        
        // Script Content Text View
        let contentLabel = NSTextField(labelWithString: "Script Content:")
        contentLabel.frame = NSRect(x: 20, y: 340, width: 100, height: 20)
        containerView.addSubview(contentLabel)
        
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: 560, height: 310))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.autoresizingMask = [.width, .height]
        textView.identifier = NSUserInterfaceItemIdentifier("script_content")
        
        scrollView.documentView = textView
        containerView.addSubview(scrollView)
        
        // Wire up source segmented control to show/hide fields
        sourceSegmented.target = self
        sourceSegmented.action = #selector(scriptSourceChanged(_:))
        
        return containerView
    }
    
    private func createKeyboardShortcutConfigurationView() -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
        
        let label = NSTextField(labelWithString: "Keyboard Shortcut:")
        label.frame = NSRect(x: 20, y: 100, width: 130, height: 20)
        containerView.addSubview(label)
        
        // Create a custom keyboard shortcut capture field
        let shortcutField = NSTextField(frame: NSRect(x: 160, y: 95, width: 220, height: 25))
        shortcutField.placeholderString = "Click and press shortcut"
        shortcutField.isEditable = false
        shortcutField.identifier = NSUserInterfaceItemIdentifier("shortcut")
        containerView.addSubview(shortcutField)
        
        let instructionLabel = NSTextField(labelWithString: "Click the field above and press your desired keyboard shortcut.")
        instructionLabel.frame = NSRect(x: 20, y: 50, width: 360, height: 30)
        instructionLabel.font = NSFont.systemFont(ofSize: 11)
        instructionLabel.textColor = NSColor.secondaryLabelColor
        instructionLabel.isEditable = false
        instructionLabel.isBordered = false
        instructionLabel.backgroundColor = .clear
        containerView.addSubview(instructionLabel)
        
        // Add a clear button
        let clearButton = NSButton(frame: NSRect(x: 160, y: 20, width: 80, height: 25))
        clearButton.bezelStyle = .rounded
        clearButton.title = "Clear"
        clearButton.target = self
        clearButton.action = #selector(clearKeyboardShortcut(_:))
        containerView.addSubview(clearButton)
        
        return containerView
    }
    
    private func createBundleActionsConfigurationView() -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        
        let label = NSTextField(labelWithString: "Bundle Actions:")
        label.frame = NSRect(x: 20, y: 360, width: 120, height: 20)
        containerView.addSubview(label)
        
        // Actions table
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 100, width: 560, height: 250))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        
        let tableView = NSTableView(frame: scrollView.bounds)
        tableView.identifier = NSUserInterfaceItemIdentifier("actions_table")
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        column.title = "Actions"
        column.width = 540
        tableView.addTableColumn(column)
        
        scrollView.documentView = tableView
        containerView.addSubview(scrollView)
        
        // Add/Remove buttons
        let addButton = NSButton(frame: NSRect(x: 20, y: 60, width: 100, height: 25))
        addButton.bezelStyle = .rounded
        addButton.title = "Add Action"
        addButton.target = self
        addButton.action = #selector(addBundleAction(_:))
        containerView.addSubview(addButton)
        
        let removeButton = NSButton(frame: NSRect(x: 130, y: 60, width: 100, height: 25))
        removeButton.bezelStyle = .rounded
        removeButton.title = "Remove"
        removeButton.target = self
        removeButton.action = #selector(removeBundleAction(_:))
        containerView.addSubview(removeButton)
        
        // Delay between actions
        let delayLabel = NSTextField(labelWithString: "Delay between actions:")
        delayLabel.frame = NSRect(x: 20, y: 20, width: 150, height: 20)
        containerView.addSubview(delayLabel)
        
        let delayField = NSTextField(frame: NSRect(x: 180, y: 15, width: 60, height: 25))
        delayField.stringValue = "0.2"
        delayField.identifier = NSUserInterfaceItemIdentifier("delay_between")
        containerView.addSubview(delayField)
        
        let delayUnitLabel = NSTextField(labelWithString: "seconds")
        delayUnitLabel.frame = NSRect(x: 250, y: 20, width: 60, height: 20)
        containerView.addSubview(delayUnitLabel)
        
        return containerView
    }
    
    private func createDefaultConfigurationView(for action: PluginAction) -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        var yOffset: CGFloat = 360
        
        // Create fields for each parameter
        for param in action.supportedParameters {
            let label = NSTextField(labelWithString: "\(param.name):")
            label.frame = NSRect(x: 20, y: yOffset, width: 120, height: 20)
            containerView.addSubview(label)
            
            switch param.type {
            case .string, .path, .url:
                let textField = NSTextField(frame: NSRect(x: 150, y: yOffset - 5, width: 330, height: 25))
                textField.placeholderString = param.description
                textField.identifier = NSUserInterfaceItemIdentifier(param.key)
                if let defaultValue = param.defaultValue?.value as? String {
                    textField.stringValue = defaultValue
                }
                containerView.addSubview(textField)
                
                if param.type == .path {
                    let browseButton = NSButton(frame: NSRect(x: 400, y: yOffset - 5, width: 80, height: 25))
                    browseButton.bezelStyle = .rounded
                    browseButton.title = "Browse"
                    browseButton.tag = Int(bitPattern: Unmanaged.passUnretained(textField).toOpaque())
                    browseButton.target = self
                    browseButton.action = #selector(browseForPath(_:))
                    containerView.addSubview(browseButton)
                }
                
            case .number:
                let numberField = NSTextField(frame: NSRect(x: 150, y: yOffset - 5, width: 100, height: 25))
                numberField.placeholderString = param.description
                numberField.identifier = NSUserInterfaceItemIdentifier(param.key)
                if let defaultValue = param.defaultValue?.value as? Double {
                    numberField.doubleValue = defaultValue
                }
                containerView.addSubview(numberField)
                
            case .boolean:
                let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
                checkbox.frame = NSRect(x: 150, y: yOffset - 2, width: 20, height: 20)
                checkbox.identifier = NSUserInterfaceItemIdentifier(param.key)
                if let defaultValue = param.defaultValue?.value as? Bool {
                    checkbox.state = defaultValue ? .on : .off
                }
                containerView.addSubview(checkbox)
                
            case .selection:
                let popup = NSPopUpButton(frame: NSRect(x: 150, y: yOffset - 5, width: 200, height: 25))
                popup.removeAllItems()
                if let allowedValues = param.validation?.allowedValues {
                    for value in allowedValues {
                        if let stringValue = value.value as? String {
                            popup.addItem(withTitle: stringValue)
                        }
                    }
                }
                popup.identifier = NSUserInterfaceItemIdentifier(param.key)
                if let defaultValue = param.defaultValue?.value as? String {
                    popup.selectItem(withTitle: defaultValue)
                }
                containerView.addSubview(popup)
                
            case .application:
                let appPopup = NSPopUpButton(frame: NSRect(x: 150, y: yOffset - 5, width: 250, height: 25))
                appPopup.removeAllItems()
                appPopup.identifier = NSUserInterfaceItemIdentifier(param.key)
                
                // Populate with running applications
                for app in NSWorkspace.shared.runningApplications {
                    if let name = app.localizedName, !app.isTerminated {
                        appPopup.addItem(withTitle: name)
                        appPopup.lastItem?.representedObject = app.bundleIdentifier
                    }
                }
                containerView.addSubview(appPopup)
                
            default:
                // For complex types, create a text field as fallback
                let textField = NSTextField(frame: NSRect(x: 150, y: yOffset - 5, width: 330, height: 25))
                textField.placeholderString = param.description
                textField.identifier = NSUserInterfaceItemIdentifier(param.key)
                containerView.addSubview(textField)
            }
            
            // Add description label if needed
            if !param.description.isEmpty && param.type != .boolean {
                let descLabel = NSTextField(labelWithString: param.description)
                descLabel.frame = NSRect(x: 150, y: yOffset - 30, width: 330, height: 20)
                descLabel.font = NSFont.systemFont(ofSize: 11)
                descLabel.textColor = NSColor.secondaryLabelColor
                containerView.addSubview(descLabel)
                yOffset -= 35
            } else {
                yOffset -= 30
            }
        }
        
        return containerView
    }
    
    // MARK: - UI Action Handlers
    
    @objc private func scriptSourceChanged(_ sender: NSSegmentedControl) {
        guard let containerView = sender.superview else { return }
        
        let useFile = sender.selectedSegment == 1
        
        // Find and update visibility of path-related fields
        if let pathLabel = containerView.viewWithTag(NSUserInterfaceItemIdentifier("path_label").rawValue.hashValue) as? NSTextField {
            pathLabel.isHidden = !useFile
        }
        if let pathField = containerView.viewWithTag(NSUserInterfaceItemIdentifier("script_path").rawValue.hashValue) as? NSTextField {
            pathField.isHidden = !useFile
        }
        if let browseButton = containerView.viewWithTag(NSUserInterfaceItemIdentifier("browse_button").rawValue.hashValue) as? NSButton {
            browseButton.isHidden = !useFile
        }
        
        // Update text view editability
        if let scrollView = containerView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView,
           let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = !useFile
            if useFile {
                textView.string = "[Script will be loaded from file]"
            } else {
                textView.string = ""
            }
        }
    }
    
    @objc private func browseForScriptFile(_ sender: NSButton) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.message = "Select script file"
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            // Update the path field
            if let containerView = sender.superview,
               let pathField = containerView.viewWithTag(NSUserInterfaceItemIdentifier("script_path").rawValue.hashValue) as? NSTextField {
                pathField.stringValue = url.path
                
                // Try to load and display the script content
                if let scrollView = containerView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView,
                   let textView = scrollView.documentView as? NSTextView {
                    do {
                        let content = try String(contentsOf: url)
                        textView.string = content
                    } catch {
                        textView.string = "[Unable to read file: \(error.localizedDescription)]"
                    }
                }
            }
        }
    }
    
    @objc private func browseForPath(_ sender: NSButton) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            // Get the associated text field from the button's tag
            if let textField = Unmanaged<NSTextField>.fromOpaque(UnsafeRawPointer(bitPattern: sender.tag)!).takeUnretainedValue() as NSTextField? {
                textField.stringValue = url.path
            }
        }
    }
    
    @objc private func clearKeyboardShortcut(_ sender: NSButton) {
        if let containerView = sender.superview,
           let shortcutField = containerView.viewWithTag(NSUserInterfaceItemIdentifier("shortcut").rawValue.hashValue) as? NSTextField {
            shortcutField.stringValue = ""
        }
    }
    
    @objc private func addBundleAction(_ sender: NSButton) {
        // This would open a dialog to select and configure an action to add
        // For now, just a placeholder
        NSLog("AutomationPlugin: Add bundle action clicked")
    }
    
    @objc private func removeBundleAction(_ sender: NSButton) {
        // Remove selected action from the table
        if let containerView = sender.superview,
           let scrollView = containerView.subviews.first(where: { ($0 as? NSScrollView)?.documentView is NSTableView }) as? NSScrollView,
           let tableView = scrollView.documentView as? NSTableView {
            let selectedRow = tableView.selectedRow
            if selectedRow >= 0 {
                // Remove from data source and reload table
                NSLog("AutomationPlugin: Remove action at row \(selectedRow)")
            }
        }
    }
}
