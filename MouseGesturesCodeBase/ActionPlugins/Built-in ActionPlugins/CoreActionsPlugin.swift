import Cocoa
import Carbon
import UserNotifications

// MARK: - Core Actions Plugin

/// Built-in plugin providing core system actions
class CoreActionsPlugin: NSObject, GestureActionPlugin {
    
    // MARK: - Plugin Properties
    
    let identifier = "com.mousegestures.core"
    let name = "Core Actions"
    override var description: String { "Essential system and application control actions" }
    let version = "1.1.0"
    let author = "MouseGestures"
    let category = ActionCategory.core
    let icon: NSImage? = nil
    
    // MARK: - Common Parameters
    
    private var windowTargetParameters: [ParameterDefinition] {
        [
            ParameterDefinition(
                key: "target",
                name: "Window Target",
                type: .selection,
                defaultValue: AnyCodable("frontmost"),
                description: "Which window to target",
                validation: ValidationRule(allowedValues: [
                    AnyCodable("frontmost"),
                    AnyCodable("by_age"),
                    AnyCodable("by_application"),
                    AnyCodable("by_title"),
                    AnyCodable("mouse_position")
                ]),
                group: "Target",
                displayValues: [
                    "frontmost": "Frontmost Window",
                    "by_age": "By Window Order",
                    "by_application": "By Application",
                    "by_title": "By Exact Title",
                    "mouse_position": "Under Mouse"
                ]
            ),
            ParameterDefinition(
                key: "app_bundle_id",
                name: "Application",
                type: .application,
                description: "Application to target",
                visibleWhen: ParameterVisibilityRule(key: "target", value: "by_application"),
                group: "Target"
            ),
            ParameterDefinition(
                key: "window_title",
                name: "Window Title",
                type: .string,
                description: "Title of the window to target",
                visibleWhen: ParameterVisibilityRule(key: "target", value: "by_title"),
                group: "Target"
            ),
            ParameterDefinition(
                key: "window_age",
                name: "Window Order",
                type: .number,
                defaultValue: AnyCodable(1),
                description: "1 = frontmost, 2 = second, etc.",
                validation: ValidationRule(minValue: 1, maxValue: 20),
                visibleWhen: ParameterVisibilityRule(key: "target", value: "by_age"),
                group: "Target"
            )
        ]
    }
    
    // MARK: - Actions
    
    lazy var providedActions: [PluginAction] = [
        // MARK: Window Actions — hidden: moved to com.mousegestures.window (backward-compat aliases)
        PluginAction(id: "close_window", name: "Close Window",      description: "Close a window",           requiresParameters: true, supportedParameters: windowTargetParameters, icon: "xmark.circle",                                   hidden: true),
        PluginAction(id: "minimize",     name: "Minimize Window",   description: "Minimize a window",        requiresParameters: true, supportedParameters: windowTargetParameters, icon: "minus.circle",                                    hidden: true),
        PluginAction(id: "maximize",     name: "Maximize Window",   description: "Maximize a window",        requiresParameters: true, supportedParameters: windowTargetParameters, icon: "plus.circle",                                     hidden: true),
        PluginAction(id: "fullscreen",   name: "Toggle Fullscreen", description: "Toggle fullscreen mode",   requiresParameters: true, supportedParameters: windowTargetParameters, icon: "arrow.up.left.and.arrow.down.right",              hidden: true),
        PluginAction(
            id: "hide_app",
            name: "Hide Application",
            description: "Hide the active application",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "target",
                    name: "Target",
                    type: .selection,
                    defaultValue: AnyCodable("frontmost"),
                    description: "Which application to hide",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("frontmost"),
                        AnyCodable("specific"),
                        AnyCodable("all_except_finder")
                    ]),
                    displayValues: [
                        "frontmost": "Frontmost App",
                        "specific": "Specific App",
                        "all_except_finder": "All Except Finder"
                    ]
                ),
                ParameterDefinition(
                    key: "app_bundle_id",
                    name: "Application",
                    type: .application,
                    description: "Application to hide when using specific target",
                    visibleWhen: ParameterVisibilityRule(key: "target", value: "specific")
                )
            ],
            icon: "eye.slash"
        ),
        
        // MARK: App Actions
        PluginAction(
            id: "quit_app",
            name: "Quit Application",
            description: "Quit an application",
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
                    ]),
                    displayValues: ["frontmost": "Frontmost App", "specific": "Specific App", "all_except_finder": "All Except Finder"]
                ),
                ParameterDefinition(
                    key: "app_bundle_id",
                    name: "Application",
                    type: .application,
                    description: "Application to quit (when targeting specific app)",
                    visibleWhen: ParameterVisibilityRule(key: "target", value: "specific")
                )
            ],
            icon: "xmark.app"
        ),
        
        // MARK: System UI
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
        
        // MARK: Cycle Window (replaces next_window / previous_window)
        PluginAction(
            id: "cycle_window",
            name: "Cycle Window",
            description: "Switch to the next or previous window",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "direction",
                    name: "Direction",
                    type: .selection,
                    defaultValue: AnyCodable("forward"),
                    description: "Which direction to cycle",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("forward"),
                        AnyCodable("backward")
                    ]),
                    displayValues: ["forward": "Forward", "backward": "Backward"]
                ),
                ParameterDefinition(
                    key: "scope",
                    name: "Application",
                    type: .selection,
                    defaultValue: AnyCodable("current"),
                    description: "Which app's windows to cycle",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("current"),
                        AnyCodable("specific"),
                        AnyCodable("all_apps")
                    ]),
                    displayValues: ["current": "Current App", "specific": "Specific App", "all_apps": "All Windows"]
                ),
                ParameterDefinition(
                    key: "app_bundle_id",
                    name: "Application",
                    type: .application,
                    description: "Application whose windows to cycle",
                    visibleWhen: ParameterVisibilityRule(key: "scope", value: "specific")
                )
            ],
            supportsRepeat: true,
            icon: "arrow.right.circle"
        ),
        
        // MARK: Cycle Space (replaces next_space / previous_space)
        PluginAction(
            id: "cycle_space",
            name: "Cycle Space",
            description: "Move to the next or previous desktop space",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "direction",
                    name: "Direction",
                    type: .selection,
                    defaultValue: AnyCodable("next"),
                    description: "Which direction to move",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("next"),
                        AnyCodable("previous")
                    ]),
                    displayValues: ["next": "Next", "previous": "Previous"]
                )
            ],
            supportsRepeat: true,
            icon: "arrow.right.square"
        ),
        
        // MARK: System
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
        ),
        
        // MARK: Switch Profile
        PluginAction(
            id: "switch_profile",
            name: "Switch Profile",
            description: "Switch to a specific, next, or previous gesture profile",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "mode",
                    name: "Mode",
                    type: .selection,
                    defaultValue: AnyCodable("specific"),
                    description: "How to select the target profile",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("specific"),
                        AnyCodable("next"),
                        AnyCodable("previous")
                    ]),
                    displayValues: ["specific": "Specific Profile", "next": "Next Profile", "previous": "Previous Profile"]
                ),
                ParameterDefinition(
                    key: "profile_name",
                    name: "Profile",
                    type: .profile,
                    description: "Select profile to switch to",
                    visibleWhen: ParameterVisibilityRule(key: "mode", value: "specific")
                ),
                ParameterDefinition(
                    key: "show_notification",
                    name: "Show Notification",
                    type: .boolean,
                    defaultValue: AnyCodable(true),
                    description: "Show notification when profile switches"
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
        switch action.id {
            
        // MARK: Window Actions
        case "close_window":
            closeWindow(target: parseWindowTarget(from: parameters), context: context)
            
        case "minimize":
            minimizeWindow(target: parseWindowTarget(from: parameters), context: context)
            
        case "maximize":
            maximizeWindow(target: parseWindowTarget(from: parameters), context: context)
            
        case "fullscreen":
            toggleFullscreen(target: parseWindowTarget(from: parameters), context: context)
            
        case "hide_app":
            let target = parameters.string(for: "target") ?? "frontmost"
            let bundleId = parameters.string(for: "app_bundle_id")
            hideApplication(target: target, bundleId: bundleId, context: context)
            
        // MARK: App Actions
        case "quit_app":
            let target = parameters.string(for: "target") ?? "frontmost"
            let bundleId = parameters.string(for: "app_bundle_id")
            quitApplication(target: target, bundleId: bundleId, context: context)
            
        // MARK: System UI
        case "mission_control":
            activateMissionControl(context: context)
        case "show_desktop":
            showDesktop(context: context)
        case "app_expose":
            activateAppExpose(context: context)
            
        // MARK: Cycle Window
        case "cycle_window":
            let forward = (parameters.string(for: "direction") ?? "forward") == "forward"
            let scope = parameters.string(for: "scope") ?? "current"
            if scope == "all_apps" {
                cycleAcrossAllWindows(forward: forward, context: context)
            } else {
                let appBundleId = scope == "specific" ? parameters.string(for: "app_bundle_id") : nil
                cycleWindows(forward: forward, appBundleId: appBundleId, context: context)
            }
            
        // MARK: Cycle Space
        case "cycle_space":
            let next = (parameters.string(for: "direction") ?? "next") == "next"
            moveToSpace(next: next, context: context)
            
        // MARK: System
        case "lock_screen":
            lockScreen(context: context)
        case "sleep_display":
            sleepDisplay(context: context)
        case "empty_trash":
            let confirm = parameters.bool(for: "confirm") ?? true
            emptyTrash(showConfirmation: confirm, context: context)
            
        // MARK: Profile
        case "switch_profile":
            let showNotification = parameters.bool(for: "show_notification") ?? true
            let mode = parameters.string(for: "mode") ?? "specific"
            switchProfile(mode: mode, profileName: parameters.string(for: "profile_name"), showNotification: showNotification, context: context)
            
        default:
            throw PluginError.actionNotFound(action.id)
        }
    }
    
    func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        switch action.id {
        case "quit_app":
            if parameters.string(for: "target") == "specific" && parameters.string(for: "app_bundle_id") == nil {
                return .invalid(error: "An application must be specified")
            }
        case "hide_app":
            if parameters.string(for: "target") == "specific" && parameters.string(for: "app_bundle_id") == nil {
                return .invalid(error: "An application must be specified")
            }
        case "switch_profile":
            let mode = parameters.string(for: "mode") ?? "specific"
            if mode == "specific" && (parameters.string(for: "profile_name") ?? "").isEmpty {
                return .invalid(error: "A profile must be selected")
            }
        default:
            break
        }
        return .valid
    }
    
    func configurationView(for action: PluginAction) -> NSView? {
        return nil
    }
    
    // MARK: - Window Target Helpers
    
    private func parseWindowTarget(from parameters: ActionParameters) -> WindowTarget {
        let typeStr = parameters.string(for: "target") ?? "frontmost"
        return WindowTarget(
            typeStr: typeStr,
            bundleId: parameters.string(for: "app_bundle_id"),
            title: parameters.string(for: "window_title"),
            age: parameters.number(for: "window_age").map { Int($0) }
        )
    }
    
    /// Lightweight target descriptor used by Core plugin (does not depend on WindowTargeting)
    private struct WindowTarget {
        enum Kind { case frontmost, byAge(Int), byApplication(String), byTitle(String), mousePosition }
        let kind: Kind
        
        init(typeStr: String, bundleId: String?, title: String?, age: Int?) {
            switch typeStr {
            case "by_age":          self.kind = .byAge(age ?? 1)
            case "by_application":  self.kind = bundleId.map { .byApplication($0) } ?? .frontmost
            case "by_title":        self.kind = title.map { .byTitle($0) } ?? .frontmost
            case "mouse_position":  self.kind = .mousePosition
            default:                self.kind = .frontmost
            }
        }
    }
    
    /// Returns the AXUIElement for the target window, falling back to frontmost.
    private func resolveTargetWindow(_ target: WindowTarget, context: PluginContext) -> AXUIElement? {
        switch target.kind {
        case .frontmost, .mousePosition:
            guard let app = context.getFrontmostApplication() else { return nil }
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            guard let wv = context.getAccessibilityAttribute(appEl, attribute: kAXFocusedWindowAttribute as String) else { return nil }
            // swiftlint:disable:next force_cast
            return unsafeBitCast(wv, to: AXUIElement.self)
            
        case .byAge(let age):
            guard let app = context.getFrontmostApplication() else { return nil }
            let windows = context.getWindowsForApplication(app.processIdentifier)
            let idx = age - 1
            return idx < windows.count ? windows[idx] : windows.first
            
        case .byApplication(let bundleId):
            guard let app = context.getRunningApplications().first(where: { $0.bundleIdentifier == bundleId }) else { return nil }
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            guard let wv = context.getAccessibilityAttribute(appEl, attribute: kAXFocusedWindowAttribute as String) else { return nil }
            // swiftlint:disable:next force_cast
            return unsafeBitCast(wv, to: AXUIElement.self)
            
        case .byTitle(let title):
            for (window, _) in context.getAllVisibleWindows() {
                if let tv = context.getAccessibilityAttribute(window, attribute: kAXTitleAttribute as String) as? String,
                   tv == title { return window }
            }
            return nil
        }
    }
    
    // MARK: - Window Action Implementations
    
    private func closeWindow(target: WindowTarget, context: PluginContext) {
        guard let window = resolveTargetWindow(target, context: context) else {
            context.sendKeyboardShortcut(keyCode: 13, modifiers: [.maskCommand])
            return
        }
        if let btnObj = context.getAccessibilityAttribute(window, attribute: kAXCloseButtonAttribute as String) {
            let btn = unsafeBitCast(btnObj, to: AXUIElement.self)
            _ = context.performAccessibilityAction(btn, action: kAXPressAction as String)
        } else {
            context.sendKeyboardShortcut(keyCode: 13, modifiers: [.maskCommand])
        }
    }
    
    private func minimizeWindow(target: WindowTarget, context: PluginContext) {
        guard let window = resolveTargetWindow(target, context: context) else {
            context.sendKeyboardShortcut(keyCode: 46, modifiers: [.maskCommand])
            return
        }
        _ = context.setAccessibilityAttribute(window, attribute: kAXMinimizedAttribute as String, value: true as CFBoolean)
    }
    
    private func maximizeWindow(target: WindowTarget, context: PluginContext) {
        guard let window = resolveTargetWindow(target, context: context),
              let screen = NSScreen.main else {
            return
        }
        let frame = screen.visibleFrame
        var position = frame.origin
        var size     = frame.size
        if let posVal = AXValueCreate(.cgPoint, &position) {
            _ = context.setAccessibilityAttribute(window, attribute: kAXPositionAttribute as String, value: posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            _ = context.setAccessibilityAttribute(window, attribute: kAXSizeAttribute as String, value: sizeVal)
        }
    }
    
    private func toggleFullscreen(target: WindowTarget, context: PluginContext) {
        // If targeting a specific app, activate it first
        if case .byApplication(let bundleId) = target.kind,
           let app = context.getRunningApplications().first(where: { $0.bundleIdentifier == bundleId }) {
            app.activate(options: [])
            usleep(100_000)
        }
        // Try pressing the AX full screen button; falls back to keyboard when hidden (e.g. already fullscreen)
        if let window = resolveTargetWindow(target, context: context),
           let btnObj = context.getAccessibilityAttribute(window, attribute: "AXFullScreenButton") {
            let btn = unsafeBitCast(btnObj, to: AXUIElement.self)
            if context.performAccessibilityAction(btn, action: kAXPressAction as String) { return }
        }
        context.sendKeyboardShortcut(keyCode: 3, modifiers: [.maskControl, .maskCommand])
    }
    
    private func hideApplication(target: String, bundleId: String?, context: PluginContext) {
        switch target {
        case "specific":
            guard let bid = bundleId else { return }
            if let app = context.getRunningApplications().first(where: { $0.bundleIdentifier == bid }) {
                _ = context.hideApplication(app)
            }
        case "all_except_finder":
            context.getRunningApplications().forEach { app in
                if app.activationPolicy == .regular,
                   app.bundleIdentifier != "com.apple.finder",
                   app.bundleIdentifier != Bundle.main.bundleIdentifier {
                    _ = context.hideApplication(app)
                }
            }
        default: // frontmost
            if let app = context.getFrontmostApplication() {
                _ = context.hideApplication(app)
            }
        }
    }
    
    // MARK: - App Actions
    
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
            guard let bid = bundleId, bid != "com.apple.finder" else { return }
            context.getRunningApplications()
                .filter { $0.bundleIdentifier == bid }
                .forEach { _ = context.terminateApplication($0) }
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
    
    // MARK: - System UI
    
    private func activateMissionControl(context: PluginContext) {
        // Launch Mission Control app directly (most reliable across shortcut configurations)
        let mcURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        if NSWorkspace.shared.open(mcURL) { return }
        // Fallback: Ctrl+Up
        context.sendKeyboardShortcut(keyCode: 126, modifiers: [.maskControl])
    }
    
    private func showDesktop(context: PluginContext) {
        // F11 (key code 103) is mapped to Show Desktop on macOS.
        // Wait for modifiers to release so F11 isn't interpreted as a modified key.
        waitForModifierRelease()
        do {
            try context.executeAppleScript("""
                tell application "System Events"
                    key code 103
                end tell
            """)
        } catch {
            // Fallback: Cmd+F3 (older Expose Show Desktop shortcut)
            context.sendKeyboardShortcut(keyCode: 99, modifiers: [.maskCommand])
        }
    }
    
    private func activateAppExpose(context: PluginContext) {
        // System Events is sensitive to physically-held modifiers;
        // wait for all modifier keys to be released first.
        waitForModifierRelease()
        do {
            try context.executeAppleScript("""
                tell application "System Events"
                    key code 125 using {control down}
                end tell
            """)
        } catch {
            context.sendKeyboardShortcut(keyCode: 125, modifiers: [.maskControl])
        }
    }
    
    private func cycleAcrossAllWindows(forward: Bool, context: PluginContext) {
        // Get all visible windows sorted by front-to-back order and find the current frontmost
        let allWindows = context.getAllVisibleWindows()
        guard !allWindows.isEmpty else { return }
        // Find current frontmost window
        let frontPid = context.getFrontmostApplication()?.processIdentifier
        let currentIdx = allWindows.firstIndex { _, pid in pid == frontPid } ?? 0
        let nextIdx = forward
            ? (currentIdx + 1) % allWindows.count
            : (currentIdx - 1 + allWindows.count) % allWindows.count
        let (nextWindow, nextPid) = allWindows[nextIdx]
        // Activate the target app
        if let app = context.getRunningApplications().first(where: { $0.processIdentifier == nextPid }) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        // Raise the window
        _ = context.performAccessibilityAction(nextWindow, action: kAXRaiseAction as String)
    }

    private func cycleWindows(forward: Bool, appBundleId: String? = nil, context: PluginContext) {
        // Activate specific app first if requested
        if let bundleId = appBundleId,
           let app = context.getRunningApplications().first(where: { $0.bundleIdentifier == bundleId }) {
            app.activate(options: [.activateIgnoringOtherApps])
            usleep(150_000)
        }
        if forward {
            context.sendKeyboardShortcut(keyCode: 50, modifiers: [.maskCommand])           // Cmd+`
        } else {
            context.sendKeyboardShortcut(keyCode: 50, modifiers: [.maskCommand, .maskShift]) // Cmd+Shift+`
        }
    }
    
    private func moveToSpace(next: Bool, context: PluginContext) {
        // System Events is sensitive to physically-held modifiers;
        // wait for all modifier keys to be released first.
        waitForModifierRelease()
        let keyCode = next ? 124 : 123 // Right / Left arrow
        do {
            try context.executeAppleScript("""
                tell application "System Events"
                    key code \(keyCode) using {control down}
                end tell
            """)
        } catch {
            context.sendKeyboardShortcut(keyCode: CGKeyCode(keyCode), modifiers: [.maskControl])
        }
    }
    
    // MARK: - System
    
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
    
    // MARK: - Profile Management
    
    private func switchProfile(mode: String, profileName: String?, showNotification: Bool, context: PluginContext) {
        let profiles = context.getProfiles()
        guard !profiles.isEmpty else { return }
        
        let targetProfile: [String: Any]?
        
        switch mode {
        case "next", "previous":
            let currentId = context.getActiveProfileId()
            let currentIndex = profiles.firstIndex(where: {
                ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == currentId
            }) ?? 0
            let targetIndex = mode == "next"
                ? (currentIndex + 1) % profiles.count
                : (currentIndex > 0 ? currentIndex - 1 : profiles.count - 1)
            targetProfile = profiles[targetIndex]
        default: // "specific"
            guard let name = profileName, !name.isEmpty else {
                context.logger.log("switch_profile: no profile name specified", file: #file, function: #function, line: #line)
                return
            }
            targetProfile = profiles.first(where: {
                ($0["name"] as? String)?.lowercased() == name.lowercased()
            })
            if targetProfile == nil {
                context.logger.log("No profile found with name: \(name)", file: #file, function: #function, line: #line)
                return
            }
        }
        
        if let target = targetProfile,
           let idStr = target["id"] as? String,
           let profileId = UUID(uuidString: idStr),
           let name = target["name"] as? String {
            context.applyProfile(profileId: profileId)
            context.saveConfiguration()
            context.postNotification(name: NSNotification.Name("GestureConfigurationChanged"), userInfo: nil)
            if showNotification {
                sendProfileNotification(profileName: name)
            }
        }
    }
    
    /// Send a native macOS notification for profile switch
    private func sendProfileNotification(profileName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Profile Switched"
        content.body = profileName
        content.sound = nil
        
        let request = UNNotificationRequest(
            identifier: "profile-switch-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                log.log("Failed to show profile notification: \(error)")
            }
        }
        
        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [request.identifier])
        }
    }
}
