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
                    ]),
                    displayValues: [
                        "applescript": "AppleScript",
                        "shell": "Shell Script",
                        "javascript": "JavaScript (JXA)",
                        "python": "Python"
                    ]
                ),
                ParameterDefinition(
                    key: "use_file",
                    name: "Load from File",
                    type: .boolean,
                    defaultValue: AnyCodable(false),
                    description: "Load script from an external file instead of inline"
                ),
                ParameterDefinition(
                    key: "script_content",
                    name: "Script",
                    type: .script,
                    description: "Inline script content"
                ),
                ParameterDefinition(
                    key: "script_path",
                    name: "Script File",
                    type: .path,
                    description: "Path to script file"
                ),
                ParameterDefinition(
                    key: "display_output",
                    name: "Display Output",
                    type: .boolean,
                    defaultValue: AnyCodable(false),
                    description: "Show script output in a notification"
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
                    ]),
                    displayValues: [
                        "copy": "Copy",
                        "paste": "Paste",
                        "cut": "Cut",
                        "clear": "Clear Clipboard",
                        "set_text": "Set Custom Text"
                    ]
                ),
                ParameterDefinition(
                    key: "text",
                    name: "Text",
                    type: .string,
                    description: "Text to set on clipboard",
                    visibleWhen: ParameterVisibilityRule(key: "action", value: "set_text")
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
            let displayOutput = parameters.bool(for: "display_output") ?? false
            
            if useFile {
                if let path = parameters.string(for: "script_path") {
                    runScriptFile(at: path, type: scriptType, displayOutput: displayOutput, context: context)
                }
            } else {
                if let content = parameters.string(for: "script_content") {
                    runScriptContent(content, type: scriptType, displayOutput: displayOutput, context: context)
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
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        
        // Build display string using centralized utilities
        var modParts: [String] = []
        if flags.contains(.maskControl) { modParts.append("⌃") }
        if flags.contains(.maskAlternate) { modParts.append("⌥") }
        if flags.contains(.maskShift) { modParts.append("⇧") }
        if flags.contains(.maskCommand) { modParts.append("⌘") }
        modParts.append(keyCode.displayString)
        
        let displayString = modParts.joined()
        
        return KeyboardShortcut(
            keyCode: keyCode,
            modifiers: flags,
            displayString: displayString
        )
    }
    
    private func executeKeyboardShortcut(_ shortcut: KeyboardShortcut) {
        // Physical modifiers are already released by the sandbox before we get here.
        guard let source = CGEventSource(stateID: .privateState) else { return }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else { return }
        keyDown.flags = shortcut.modifiers
        keyUp.flags = shortcut.modifiers
        keyDown.post(tap: .cghidEventTap)
        usleep(100_000)
        keyUp.post(tap: .cghidEventTap)
    }
    
    private func runShortcut(name: String, input: String?) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Primary: use the shortcuts CLI tool
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
                    // Fallback to AppleScript with Shortcuts Events
                    self.runShortcutViaAppleScript(name: name, input: input)
                }
            } catch {
                self.runShortcutViaAppleScript(name: name, input: input)
            }
        }
    }
    
    private func runShortcutViaAppleScript(name: String, input: String?) {
        // Escape double quotes in the shortcut name for AppleScript
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        
        let script: String
        if let input = input {
            let escapedInput = input.replacingOccurrences(of: "\"", with: "\\\"")
            script = """
                tell application "Shortcuts Events"
                    run shortcut "\(escapedName)" with input "\(escapedInput)"
                end tell
            """
        } else {
            script = """
                tell application "Shortcuts Events"
                    run shortcut "\(escapedName)"
                end tell
            """
        }
        
        executeAppleScript(script)
    }
    
    private func runScriptContent(_ content: String, type: String, displayOutput: Bool = false, context: PluginContext) {
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
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            if displayOutput {
                process.standardOutput = outputPipe
                process.standardError = errorPipe
            }
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if displayOutput {
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    let displayText: String
                    if process.terminationStatus != 0 && !errorOutput.isEmpty {
                        displayText = "Error: \(errorOutput)"
                    } else if !output.isEmpty {
                        // Truncate long output for notification display
                        displayText = output.count > 200 ? String(output.prefix(200)) + "…" : output
                    } else {
                        displayText = "Script completed (exit code \(process.terminationStatus))"
                    }
                    
                    context.showNotification(
                        title: "Script Output",
                        message: displayText,
                        style: process.terminationStatus == 0 ? .info : .warning
                    )
                }
            } catch {
                context.logger.log("Error executing script: \(error)", file: #file, function: #function, line: #line)
                if displayOutput {
                    context.showNotification(title: "Script Error", message: error.localizedDescription, style: .error)
                }
            }
        }
    }
    
    private func runScriptFile(at path: String, type: String, displayOutput: Bool = false, context: PluginContext) {
        guard FileManager.default.fileExists(atPath: path) else {
            context.logger.log("Script file not found: \(path)", file: #file, function: #function, line: #line)
            return
        }
        
        do {
            let content = try String(contentsOfFile: path)
            runScriptContent(content, type: type, displayOutput: displayOutput, context: context)
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
        // Normalize URL: add https:// scheme if missing
        var normalizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedURL.contains("://") {
            // Check if it looks like a domain (contains a dot but isn't a file path)
            if normalizedURL.contains(".") && !normalizedURL.hasPrefix("/") {
                normalizedURL = "https://\(normalizedURL)"
            } else if !normalizedURL.isEmpty {
                // Doesn't look like a URL — treat as a web search query
                let encoded = normalizedURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? normalizedURL
                normalizedURL = "https://www.google.com/search?q=\(encoded)"
            }
        }
        
        guard let url = URL(string: normalizedURL) else {
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
    
    private func sendKeyboardShortcut(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        // Physical modifiers are already released by the sandbox before we get here.
        guard let source = CGEventSource(stateID: .privateState) else { return }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        usleep(50_000)
        keyUp.post(tap: .cghidEventTap)
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
    
}
