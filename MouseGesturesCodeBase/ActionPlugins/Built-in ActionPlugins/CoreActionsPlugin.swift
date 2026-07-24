import Cocoa
import Carbon

// MARK: - Core Actions Plugin

/// Legacy action identifiers, kept alive as hidden backward-compat aliases so
/// gestures saved before the plugin reorganization keep resolving.
///
/// Every action here used to be implemented directly in this plugin; the
/// real implementations have all moved to the plugin that actually owns that
/// domain (WindowManagementPlugin for app/window arrangement,
/// SystemControlPlugin for system-level actions, AutomationPlugin for
/// switch_profile). Each hidden case below just forwards to the new
/// identifier via `PluginManager.executeAction(identifier:parameters:)`, so
/// there is a single implementation to maintain, not two. This plugin has no
/// actions of its own left; it exists purely so those old identifiers keep
/// resolving.
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
        // MARK: hidden — moved to com.mousegestures.window (backward-compat aliases)
        PluginAction(id: "close_window", name: "Close Window", description: "Close a window", requiresParameters: true, supportedParameters: windowTargetParameters, icon: "xmark.circle", hidden: true),
        PluginAction(id: "minimize", name: "Minimize Window", description: "Minimize a window", requiresParameters: true, supportedParameters: windowTargetParameters, icon: "minus.circle", hidden: true),
        PluginAction(id: "maximize", name: "Maximize Window", description: "Maximize a window", requiresParameters: true, supportedParameters: windowTargetParameters, icon: "plus.circle", hidden: true),
        PluginAction(id: "fullscreen", name: "Toggle Fullscreen", description: "Toggle fullscreen mode", requiresParameters: true, supportedParameters: windowTargetParameters, icon: "arrow.up.left.and.arrow.down.right", hidden: true),
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
            icon: "eye.slash",
            hidden: true
        ),
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
            icon: "xmark.app",
            hidden: true
        ),
        PluginAction(id: "mission_control", name: "Mission Control", description: "Show Mission Control", icon: "rectangle.3.group", hidden: true),
        PluginAction(id: "show_desktop", name: "Show Desktop", description: "Show the desktop", icon: "menubar.dock.rectangle", hidden: true),
        PluginAction(id: "app_expose", name: "Application Windows", description: "Show all windows of current application", icon: "rectangle.stack", hidden: true),
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
            icon: "arrow.right.circle",
            hidden: true
        ),
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
            icon: "arrow.right.square",
            hidden: true
        ),

        // MARK: hidden — moved to com.mousegestures.system (backward-compat aliases)
        PluginAction(id: "lock_screen", name: "Lock Screen", description: "Lock the screen", icon: "lock", hidden: true),
        PluginAction(id: "sleep_display", name: "Sleep Display", description: "Put the display(s) to sleep without sleeping the computer", icon: "moon", hidden: true),
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
            icon: "trash",
            hidden: true
        ),

        // MARK: hidden — moved to com.mousegestures.automation (backward-compat alias)
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
            icon: "person.crop.circle.fill",
            hidden: true
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

        // MARK: Forwarded to com.mousegestures.window
        case "close_window", "minimize", "maximize", "fullscreen",
             "hide_app", "quit_app", "mission_control", "show_desktop", "app_expose",
             "cycle_window", "cycle_space":
            try PluginManager.shared.executeAction(identifier: "com.mousegestures.window.\(action.id)", parameters: parameters)

        // MARK: Forwarded to com.mousegestures.system
        case "lock_screen", "sleep_display", "empty_trash":
            try PluginManager.shared.executeAction(identifier: "com.mousegestures.system.\(action.id)", parameters: parameters)

        // MARK: Forwarded to com.mousegestures.automation
        case "switch_profile":
            try PluginManager.shared.executeAction(identifier: "com.mousegestures.automation.switch_profile", parameters: parameters)

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
        default:
            break
        }
        return .valid
    }

    func configurationView(for action: PluginAction) -> NSView? {
        return nil
    }
}
