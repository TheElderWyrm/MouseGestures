import Cocoa

/// Built-in plugin for browser-specific actions
class BrowserActionsPlugin: NSObject, GestureActionPlugin {
    
    // MARK: - Plugin Properties
    
    let identifier = "com.mousegestures.browser"
    let name = "Browser Actions"
    override var description: String { "Specialized actions for web browsers (Safari, Chrome, etc.)" }
    let version = "1.0.0"
    let author = "MouseGestures"
    let category = ActionCategory.application
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
                        AnyCodable("home")
                    ]),
                    displayValues: [
                        "back": "Go Back",
                        "forward": "Go Forward",
                        "refresh": "Reload Page",
                        "home": "Go Home"
                    ]
                )
            ],
            icon: "safari"
        ),
        
        PluginAction(
            id: "tab_management",
            name: "Tab Management",
            description: "Control browser tabs",
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
                        AnyCodable("next_tab"),
                        AnyCodable("previous_tab"),
                        AnyCodable("reopen_closed_tab")
                    ]),
                    displayValues: [
                        "new_tab": "New Tab",
                        "close_tab": "Close Tab",
                        "next_tab": "Next Tab",
                        "previous_tab": "Previous Tab",
                        "reopen_closed_tab": "Reopen Last Closed Tab"
                    ]
                )
            ],
            icon: "plus.square.on.square"
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
            context.sendKeyboardShortcut(keyCode: 0x7D, modifiers: .maskCommand) // Cmd + ]
        case "refresh":
            context.sendKeyboardShortcut(keyCode: 0x0F, modifiers: .maskCommand) // Cmd + R
        case "home":
            context.sendKeyboardShortcut(keyCode: 0x04, modifiers: [.maskCommand, .maskShift]) // Cmd + Shift + H
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
        case "next_tab":
            context.sendKeyboardShortcut(keyCode: 0x30, modifiers: .maskControl) // Ctrl + Tab
        case "previous_tab":
            context.sendKeyboardShortcut(keyCode: 0x30, modifiers: [.maskControl, .maskShift]) // Ctrl + Shift + Tab
        case "reopen_closed_tab":
            context.sendKeyboardShortcut(keyCode: 0x11, modifiers: [.maskCommand, .maskShift]) // Cmd + Shift + T
        default:
            break
        }
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
