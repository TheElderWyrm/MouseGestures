import Cocoa

/// Built-in plugin for browser-specific actions
class BrowserActionsPlugin: NSObject, GestureActionPlugin {

    // MARK: - Plugin Properties

    let identifier = "com.mousegestures.browser"
    let name = "Browser Actions"
    override var description: String { "Specialized actions for web browsers (Safari, Chrome, etc.)" }
    let version = "1.0.0"
    let author = "MouseGestures"
    let category = ActionCategory.browser
    let icon: NSImage? = nil

    // MARK: - Actions

    lazy var providedActions: [PluginAction] = [
        PluginAction(
            id: "navigation",
            name: "Browser Navigation",
            description: "Go back, forward, or refresh in the active browser",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "action",
                    name: "Action",
                    type: .selection,
                    defaultValue: AnyCodable("back"),
                    description: "Navigation action to perform",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("back"),
                        AnyCodable("forward"),
                        AnyCodable("refresh"),
                        AnyCodable("home"),
                        AnyCodable("focus_address_bar")
                    ]),
                    displayValues: [
                        "back": "Go Back",
                        "forward": "Go Forward",
                        "refresh": "Reload Page",
                        "home": "Go Home",
                        "focus_address_bar": "Focus Address Bar"
                    ]
                )
            ],
            icon: "safari"
        ),

        PluginAction(
            id: "tab_management",
            name: "Tab Management",
            description: "Open, close, or reopen browser tabs",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "action",
                    name: "Action",
                    type: .selection,
                    defaultValue: AnyCodable("new_tab"),
                    description: "Tab action to perform",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("new_tab"),
                        AnyCodable("close_tab"),
                        AnyCodable("reopen_closed_tab")
                    ]),
                    displayValues: [
                        "new_tab": "New Tab",
                        "close_tab": "Close Tab",
                        "reopen_closed_tab": "Reopen Last Closed Tab"
                    ]
                )
            ],
            icon: "plus.square.on.square"
        ),

        // Split out of tab_management: switching WHICH tab is frontmost is a
        // distinct action from opening/closing tabs, and needed its own
        // parameters for moving more than one tab at a time or jumping
        // straight to a specific tab.
        PluginAction(
            id: "cycle_tab",
            name: "Switch Tab",
            description: "Move to the next tab, the previous tab, or a specific tab",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "mode",
                    name: "Mode",
                    type: .selection,
                    defaultValue: AnyCodable("next"),
                    description: "How to select the target tab",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("next"),
                        AnyCodable("previous"),
                        AnyCodable("specific")
                    ]),
                    displayValues: ["next": "Next Tab", "previous": "Previous Tab", "specific": "Specific Tab Number"]
                ),
                ParameterDefinition(
                    key: "count",
                    name: "Number of Tabs",
                    type: .number,
                    defaultValue: AnyCodable(1),
                    description: "How many tabs to move across",
                    validation: ValidationRule(minValue: 1, maxValue: 20),
                    visibleWhen: ParameterVisibilityRule(key: "mode", anyOf: ["next", "previous"])
                ),
                ParameterDefinition(
                    key: "tab_number",
                    name: "Tab Number",
                    type: .number,
                    defaultValue: AnyCodable(1),
                    description: "Which tab to jump to. 1-8 jump to that position; 9 jumps to the last tab (matches Safari/Chrome/Firefox/Edge's own Cmd+1...Cmd+9 shortcuts)",
                    validation: ValidationRule(minValue: 1, maxValue: 9),
                    visibleWhen: ParameterVisibilityRule(key: "mode", value: "specific")
                )
            ],
            supportsRepeat: true,
            icon: "arrow.left.arrow.right.square"
        ),

        PluginAction(
            id: "zoom",
            name: "Browser Zoom",
            description: "Adjust page zoom level",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "action",
                    name: "Action",
                    type: .selection,
                    defaultValue: AnyCodable("zoom_in"),
                    description: "Zoom action to perform",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("zoom_in"),
                        AnyCodable("zoom_out"),
                        AnyCodable("reset")
                    ]),
                    displayValues: [
                        "zoom_in": "Zoom In",
                        "zoom_out": "Zoom Out",
                        "reset": "Reset Zoom"
                    ]
                )
            ],
            supportsRepeat: true,
            icon: "plus.magnifyingglass"
        )
    ]

    // MARK: - Plugin Lifecycle

    func initialize(context: PluginContext) throws {
        // Initialization if needed
    }

    func cleanup() {
        // Cleanup if needed
    }

    // MARK: - Action Execution

    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "navigation":
            try executeNavigationAction(parameters: parameters, context: context)
        case "tab_management":
            try executeTabAction(parameters: parameters, context: context)
        case "cycle_tab":
            try executeCycleTabAction(parameters: parameters, context: context)
        case "zoom":
            try executeZoomAction(parameters: parameters, context: context)
        default:
            // The identifier check is handled by the PluginManager, but we should be safe
            break
        }
    }

    func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        return .valid
    }

    private func executeNavigationAction(parameters: ActionParameters, context: PluginContext) throws {
        let action = parameters.string(for: "action") ?? "back"

        switch action {
        case "back":
            context.sendKeyboardShortcut(keyCode: 0x7B, modifiers: .maskCommand) // Cmd + [
        case "forward":
            context.sendKeyboardShortcut(keyCode: 0x7C, modifiers: .maskCommand) // Cmd + Right Arrow
        case "refresh":
            context.sendKeyboardShortcut(keyCode: 0x0F, modifiers: .maskCommand) // Cmd + R
        case "home":
            context.sendKeyboardShortcut(keyCode: 0x04, modifiers: [.maskCommand, .maskShift]) // Cmd + Shift + H
        case "focus_address_bar":
            context.sendKeyboardShortcut(keyCode: 0x25, modifiers: .maskCommand) // Cmd + L
        default:
            break
        }
    }

    private func executeTabAction(parameters: ActionParameters, context: PluginContext) throws {
        let action = parameters.string(for: "action") ?? "new_tab"

        switch action {
        case "new_tab":
            context.sendKeyboardShortcut(keyCode: 0x11, modifiers: .maskCommand) // Cmd + T
        case "close_tab":
            context.sendKeyboardShortcut(keyCode: 0x0D, modifiers: .maskCommand) // Cmd + W
        case "reopen_closed_tab":
            context.sendKeyboardShortcut(keyCode: 0x11, modifiers: [.maskCommand, .maskShift]) // Cmd + Shift + T
        default:
            break
        }
    }

    private func executeCycleTabAction(parameters: ActionParameters, context: PluginContext) throws {
        let mode = parameters.string(for: "mode") ?? "next"

        switch mode {
        case "specific":
            let tabNumber = max(1, min(9, Int(parameters.number(for: "tab_number") ?? 1)))
            context.sendKeyboardShortcut(keyCode: keyCodeForDigit(tabNumber), modifiers: .maskCommand) // Cmd + 1...9
        case "previous":
            // Clamp to the declared 1...20 range: execute() never runs validate(),
            // so a hand-edited/bundle-supplied count could otherwise spin this
            // loop arbitrarily, spamming synthetic keystrokes on the exec thread.
            let count = min(20, max(1, Int(parameters.number(for: "count") ?? 1)))
            for _ in 0..<count {
                context.sendKeyboardShortcut(keyCode: 0x30, modifiers: [.maskControl, .maskShift]) // Ctrl + Shift + Tab
            }
        default: // "next"
            let count = min(20, max(1, Int(parameters.number(for: "count") ?? 1)))
            for _ in 0..<count {
                context.sendKeyboardShortcut(keyCode: 0x30, modifiers: .maskControl) // Ctrl + Tab
            }
        }
    }

    /// Virtual key codes for the digits 1-9, for jumping directly to a
    /// numbered browser tab.
    private func keyCodeForDigit(_ digit: Int) -> CGKeyCode {
        let codes: [Int: CGKeyCode] = [1: 0x12, 2: 0x13, 3: 0x14, 4: 0x15, 5: 0x17, 6: 0x16, 7: 0x1A, 8: 0x1C, 9: 0x19]
        return codes[digit] ?? 0x12
    }

    private func executeZoomAction(parameters: ActionParameters, context: PluginContext) throws {
        let action = parameters.string(for: "action") ?? "zoom_in"

        switch action {
        case "zoom_in":
            context.sendKeyboardShortcut(keyCode: 0x18, modifiers: .maskCommand) // Cmd + =
        case "zoom_out":
            context.sendKeyboardShortcut(keyCode: 0x1B, modifiers: .maskCommand) // Cmd + -
        case "reset":
            context.sendKeyboardShortcut(keyCode: 0x1D, modifiers: .maskCommand) // Cmd + 0
        default:
            break
        }
    }
}
