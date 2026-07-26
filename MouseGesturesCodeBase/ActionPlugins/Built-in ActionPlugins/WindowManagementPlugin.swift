import Cocoa
import Carbon

// MARK: - Plugin-Specific Types

/// Structure for window layouts
struct WindowLayout: Codable, Equatable {
    struct WindowInfo: Codable, Equatable {
        var appBundleIdentifier: String
        var appName: String
        var windowTitle: String?
        var position: CGPoint
        var size: CGSize
        var isMinimized: Bool
        var spaceNumber: Int?
    }

    var name: String
    var windows: [WindowInfo]
    var dateCreated: Date

    init(name: String, windows: [WindowInfo] = []) {
        self.name = name
        self.windows = windows
        self.dateCreated = Date()
    }
}

/// Structure for window size parameters
struct WindowSizeParameters: Codable, Equatable {
    var width: Int?
    var height: Int?
    var widthPercent: Int?
    var heightPercent: Int?
    var maintainAspectRatio: Bool

    init(width: Int? = nil, height: Int? = nil, widthPercent: Int? = nil, heightPercent: Int? = nil, maintainAspectRatio: Bool = false) {
        self.width = width
        self.height = height
        self.widthPercent = widthPercent
        self.heightPercent = heightPercent
        self.maintainAspectRatio = maintainAspectRatio
    }

    var displayString: String {
        var parts: [String] = []
        if let w = width { parts.append("W: \(w)px") }
        if let h = height { parts.append("H: \(h)px") }
        if let wp = widthPercent { parts.append("W: \(wp)%") }
        if let hp = heightPercent { parts.append("H: \(hp)%") }
        if maintainAspectRatio { parts.append("(Keep Ratio)") }
        return parts.joined(separator: ", ")
    }
}

/// Structure for window position parameters
struct WindowPositionParameters: Codable, Equatable {
    enum PositionType: String, Codable, CaseIterable {
        case absolute = "Absolute Position"
        case relative = "Relative to Current"
        case screenPercentage = "Screen Percentage"
        case preset = "Preset Position"
    }

    enum PresetPosition: String, Codable, CaseIterable {
        case topLeft = "Top Left"
        case topCenter = "Top Center"
        case topRight = "Top Right"
        case middleLeft = "Middle Left"
        case center = "Center"
        case middleRight = "Middle Right"
        case bottomLeft = "Bottom Left"
        case bottomCenter = "Bottom Center"
        case bottomRight = "Bottom Right"
    }

    var positionType: PositionType
    var x: Int?
    var y: Int?
    var xPercent: Int?
    var yPercent: Int?
    var preset: PresetPosition?

    init(positionType: PositionType = .absolute, x: Int? = nil, y: Int? = nil, xPercent: Int? = nil, yPercent: Int? = nil, preset: PresetPosition? = nil) {
        self.positionType = positionType
        self.x = x
        self.y = y
        self.xPercent = xPercent
        self.yPercent = yPercent
        self.preset = preset
    }

    var displayString: String {
        switch positionType {
        case .absolute:
            return "X: \(x ?? 0), Y: \(y ?? 0)"
        case .relative:
            let xStr = x ?? 0 > 0 ? "+\(x ?? 0)" : "\(x ?? 0)"
            let yStr = y ?? 0 > 0 ? "+\(y ?? 0)" : "\(y ?? 0)"
            return "X: \(xStr), Y: \(yStr)"
        case .screenPercentage:
            return "X: \(xPercent ?? 0)%, Y: \(yPercent ?? 0)%"
        case .preset:
            return preset?.rawValue ?? "Unknown"
        }
    }
}

// MARK: - Window Management Plugin

/// Built-in plugin for window management actions
class WindowManagementPlugin: NSObject, GestureActionPlugin {

    // MARK: - Plugin Properties

    let identifier = "com.mousegestures.window"
    let name = "Window Management"
    override var description: String { "Window positioning and sizing actions" }
    let version = "2.1.0"
    let author = "MouseGestures"
    let category = ActionCategory.window
    let icon: NSImage? = nil

    // MARK: - Internal State Management

    private var savedWindowPositions: [String: WindowPosition] = [:]
    private var savedLayouts: [String: WindowLayout] = [:]
    /// Frame a window had immediately before its most recent snap, keyed by
    /// owning app bundle ID. Snapping to the SAME position again while this
    /// entry is still current restores the frame instead of re-snapping —
    /// a lightweight "press again to undo" toggle. In-memory only (not
    /// persisted): it's a transient UX nicety, not durable state.
    private var lastSnapByApp: [String: (position: String, originalFrame: CGRect, snappedFrame: CGRect)] = [:]
    /// Guards the three dictionaries above. `execute()` runs on a concurrent
    /// background queue (ActionExecutionManager dispatches there), so two
    /// overlapping gesture firings — or a UI option-provider read
    /// (getAvailableLayouts/getAvailablePositionSlots, called from the main
    /// thread) racing a background write — can mutate/read these Dictionaries
    /// at the same time, which can crash. Never hold this across AX calls,
    /// disk I/O, or app-launch waits — only around the dictionary access
    /// itself (snapshot-then-release, matching the lock pattern already used
    /// for BundleActionsPlugin.activeExecutions / SpaceSentinelManager.sentinels).
    private let stateLock = NSLock()

    struct WindowPosition: Codable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let appIdentifier: String
    }

    // MARK: - Common Parameter Definitions

    private var windowTargetParameters: [ParameterDefinition] {
        [
            ParameterDefinition(
                key: "target",
                name: "Window Target",
                type: .selection,
                defaultValue: AnyCodable("frontmost"),
                description: "Which window(s) to target",
                validation: ValidationRule(allowedValues: [
                    AnyCodable("frontmost"),
                    AnyCodable("by_age"),
                    AnyCodable("by_application"),
                    AnyCodable("by_title"),
                    AnyCodable("by_title_contains"),
                    AnyCodable("all_in_app"),
                    AnyCodable("all_visible"),
                    AnyCodable("mouse_position"),
                    AnyCodable("largest"),
                    AnyCodable("smallest")
                ]),
                group: "Target",
                displayValues: [
                    "frontmost": "Frontmost Window",
                    "by_age": "By Window Order",
                    "by_application": "By Application",
                    "by_title": "By Exact Title",
                    "by_title_contains": "By Title Contains",
                    "all_in_app": "All Windows in App",
                    "all_visible": "All Visible Windows",
                    "mouse_position": "Under Mouse",
                    "largest": "Largest Window",
                    "smallest": "Smallest Window"
                ]
            ),
            ParameterDefinition(
                key: "app_bundle_id",
                name: "Application",
                type: .application,
                description: "Application to target",
                visibleWhen: ParameterVisibilityRule(key: "target", anyOf: ["by_application", "all_in_app"]),
                group: "Target"
            ),
            ParameterDefinition(
                key: "window_title",
                name: "Window Title",
                type: .string,
                description: "Title of the window to target",
                visibleWhen: ParameterVisibilityRule(key: "target", anyOf: ["by_title", "by_title_contains"]),
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

        // MARK: Window Controls (moved from Core for architectural clarity)
        PluginAction(id: "close_window", name: "Close Window", description: "Close a window", requiresParameters: true, supportedParameters: windowTargetParameters, icon: "xmark.circle"),
        PluginAction(id: "minimize", name: "Minimize Window", description: "Minimize a window", requiresParameters: true, supportedParameters: windowTargetParameters, icon: "minus.circle"),
        PluginAction(id: "maximize", name: "Maximize Window", description: "Fill screen (not fullscreen)", requiresParameters: true, supportedParameters: windowTargetParameters, icon: "plus.circle"),
        PluginAction(id: "fullscreen", name: "Toggle Fullscreen", description: "Toggle fullscreen mode", requiresParameters: true, supportedParameters: windowTargetParameters, icon: "arrow.up.left.and.arrow.down.right"),

        // MARK: Move to Display
        PluginAction(
            id: "move_to_display",
            name: "Move to Display",
            description: "Move a window to a different display",
            requiresParameters: true,
            supportedParameters: windowTargetParameters + [
                ParameterDefinition(
                    key: "display",
                    name: "Display",
                    type: .selection,
                    defaultValue: AnyCodable("next"),
                    description: "Which display to move the window to",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("next"),
                        AnyCodable("previous"),
                        AnyCodable("1"),
                        AnyCodable("2"),
                        AnyCodable("3"),
                        AnyCodable("4")
                    ]),
                    displayValues: [
                        "next": "Next Display",
                        "previous": "Previous Display",
                        "1": "Display 1",
                        "2": "Display 2",
                        "3": "Display 3",
                        "4": "Display 4"
                    ]
                )
            ],
            icon: "display.2"
        ),

        // MARK: Snap Window (replaces individual half/quarter/third actions)
        PluginAction(
            id: "snap_window",
            name: "Snap to Region",
            description: "Move window to a screen region",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "position",
                    name: "Position",
                    type: .selection,
                    defaultValue: AnyCodable("left_half"),
                    description: "Region to snap the window to",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("maximize"),
                        AnyCodable("center"),
                        AnyCodable("left_half"),
                        AnyCodable("right_half"),
                        AnyCodable("top_half"),
                        AnyCodable("bottom_half"),
                        AnyCodable("top_left"),
                        AnyCodable("top_right"),
                        AnyCodable("bottom_left"),
                        AnyCodable("bottom_right"),
                        AnyCodable("left_third"),
                        AnyCodable("center_third"),
                        AnyCodable("right_third")
                    ]),
                    displayValues: [
                        "maximize": "Fill Screen",
                        "center": "Center",
                        "left_half": "Left Half",
                        "right_half": "Right Half",
                        "top_half": "Top Half",
                        "bottom_half": "Bottom Half",
                        "top_left": "Top Left Quarter",
                        "top_right": "Top Right Quarter",
                        "bottom_left": "Bottom Left Quarter",
                        "bottom_right": "Bottom Right Quarter",
                        "left_third": "Left Third",
                        "center_third": "Center Third",
                        "right_third": "Right Third"
                    ]
                )
            ] + windowTargetParameters,
            icon: "rectangle.split.2x1"
        ),

        // MARK: Resize to Percent (replaces resize_25 / resize_50 / resize_75)
        PluginAction(
            id: "resize_to_percent",
            name: "Resize to Percent",
            description: "Resize window to a percentage of screen size",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "percent",
                    name: "Percent",
                    type: .number,
                    defaultValue: AnyCodable(50),
                    description: "Percentage of screen size",
                    validation: ValidationRule(minValue: 1, maxValue: 100),
                    suffix: "%"
                )
            ] + windowTargetParameters,
            icon: "arrow.down.right.and.arrow.up.left"
        ),

        // MARK: Adjust Size (replaces grow / shrink with configurable percent)
        PluginAction(
            id: "adjust_size",
            name: "Adjust Window Size",
            description: "Grow or shrink the window by a percentage",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "direction",
                    name: "Direction",
                    type: .selection,
                    defaultValue: AnyCodable("grow"),
                    description: "Whether to grow or shrink the window",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("grow"),
                        AnyCodable("shrink")
                    ]),
                    displayValues: ["grow": "Grow", "shrink": "Shrink"]
                ),
                ParameterDefinition(
                    key: "unit",
                    name: "Unit",
                    type: .selection,
                    defaultValue: AnyCodable("percent"),
                    description: "How to measure the adjustment",
                    validation: ValidationRule(allowedValues: [AnyCodable("percent"), AnyCodable("pixels")]),
                    displayValues: ["percent": "Percent", "pixels": "Pixels"]
                ),
                ParameterDefinition(
                    key: "percent",
                    name: "Amount",
                    type: .number,
                    defaultValue: AnyCodable(10),
                    description: "Amount to adjust",
                    validation: ValidationRule(minValue: 1),
                    visibleWhen: ParameterVisibilityRule(key: "unit", value: "percent"),
                    suffix: "%"
                ),
                ParameterDefinition(
                    key: "pixels",
                    name: "Pixels",
                    type: .number,
                    defaultValue: AnyCodable(50),
                    description: "Amount to adjust in pixels",
                    validation: ValidationRule(minValue: 1),
                    visibleWhen: ParameterVisibilityRule(key: "unit", value: "pixels"),
                    suffix: "px"
                )
            ] + windowTargetParameters,
            supportsRepeat: true,
            icon: "arrow.up.backward.and.arrow.down.forward"
        ),

        PluginAction(
            id: "switch_to_window",
            name: "Switch to Window",
            description: "Switch to a specific window",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.portrait.and.arrow.right"
        ),

        // MARK: Window Position Memory (replaces save_position / restore_position)
        PluginAction(
            id: "window_position_memory",
            name: "Window Position Memory",
            description: "Save, restore, or delete a remembered window position",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "operation",
                    name: "Operation",
                    type: .selection,
                    defaultValue: AnyCodable("save"),
                    description: "What to do with the saved position",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("save"),
                        AnyCodable("restore"),
                        AnyCodable("delete")
                    ]),
                    displayValues: ["save": "Save Position", "restore": "Restore Position", "delete": "Delete Saved"]
                ),
                ParameterDefinition(
                    key: "slot",
                    name: "Slot Name",
                    type: .string,
                    defaultValue: AnyCodable("default"),
                    description: "Named slot for the position",
                    optionProvider: "window.position_slots"
                )
            ] + windowTargetParameters,
            icon: "square.and.arrow.down"
        ),

        // MARK: Advanced Layouts (replaces save_layout / restore_layout / delete_layout)
        PluginAction(
            id: "window_layout",
            name: "Window Layout",
            description: "Save, restore, or delete a named window layout",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "operation",
                    name: "Operation",
                    type: .selection,
                    defaultValue: AnyCodable("save"),
                    description: "Layout operation to perform",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("save"),
                        AnyCodable("restore"),
                        AnyCodable("delete")
                    ]),
                    displayValues: ["save": "Save Layout", "restore": "Restore Layout", "delete": "Delete Layout"]
                ),
                ParameterDefinition(
                    key: "layout_name",
                    name: "Layout Name",
                    type: .string,
                    required: true,
                    description: "Name of the layout",
                    optionProvider: "window.layouts"
                ),
                ParameterDefinition(
                    key: "reopen_apps",
                    name: "Reopen Apps",
                    type: .boolean,
                    defaultValue: AnyCodable(true),
                    description: "Launch apps that aren't running when restoring",
                    visibleWhen: ParameterVisibilityRule(key: "operation", value: "restore")
                )
            ],
            icon: "rectangle.3.group"
        ),

        // MARK: Tile / Cascade
        PluginAction(
            id: "tile_all",
            name: "Tile Windows",
            description: "Tile windows on screen",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "scope",
                    name: "Scope",
                    type: .selection,
                    defaultValue: AnyCodable("current_app"),
                    description: "Which windows to tile",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("current_app"),
                        AnyCodable("all_windows"),
                        AnyCodable("specific_app")
                    ]),
                    displayValues: ["current_app": "Current App", "all_windows": "All Windows", "specific_app": "Specific App"]
                ),
                ParameterDefinition(
                    key: "tile_app_bundle_id",
                    name: "Application",
                    type: .application,
                    description: "App whose windows to tile",
                    visibleWhen: ParameterVisibilityRule(key: "scope", value: "specific_app")
                ),
                ParameterDefinition(
                    key: "resize_windows",
                    name: "Resize Windows",
                    type: .boolean,
                    defaultValue: AnyCodable(true),
                    description: "Resize windows to fill the tiled grid"
                ),
                ParameterDefinition(
                    key: "constant_size",
                    name: "Constant Size",
                    type: .boolean,
                    defaultValue: AnyCodable(false),
                    description: "Tile each window to a fixed size instead of auto-filling",
                    visibleWhen: ParameterVisibilityRule(key: "resize_windows", value: "true")
                ),
                ParameterDefinition(
                    key: "tile_width",
                    name: "Tile Width",
                    type: .number,
                    defaultValue: AnyCodable(800),
                    description: "Width for each tiled window",
                    validation: ValidationRule(minValue: 100),
                    visibleWhen: ParameterVisibilityRule(key: "constant_size", value: "true"),
                    suffix: "px"
                ),
                ParameterDefinition(
                    key: "tile_height",
                    name: "Tile Height",
                    type: .number,
                    defaultValue: AnyCodable(600),
                    description: "Height for each tiled window",
                    validation: ValidationRule(minValue: 100),
                    visibleWhen: ParameterVisibilityRule(key: "constant_size", value: "true"),
                    suffix: "px"
                )
            ] + windowTargetParameters,
            icon: "rectangle.split.2x2"
        ),
        PluginAction(
            id: "cascade",
            name: "Cascade Windows",
            description: "Cascade windows",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "scope",
                    name: "Scope",
                    type: .selection,
                    defaultValue: AnyCodable("current_app"),
                    description: "Which windows to cascade",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("current_app"),
                        AnyCodable("all_windows")
                    ]),
                    displayValues: ["current_app": "Current App", "all_windows": "All Windows"]
                ),
                ParameterDefinition(
                    key: "resize_windows",
                    name: "Resize Windows",
                    type: .boolean,
                    defaultValue: AnyCodable(true),
                    description: "Resize windows to a uniform size when cascading"
                )
            ],
            icon: "rectangle.stack"
        ),

        // MARK: Custom Size / Position
        PluginAction(
            id: "set_size",
            name: "Set Window Size",
            description: "Set custom window size",
            requiresParameters: true,
            supportedParameters: windowTargetParameters + [
                ParameterDefinition(
                    key: "width",
                    name: "Width",
                    type: .number,
                    required: false,
                    description: "Window width in pixels",
                    validation: ValidationRule(minValue: 0),
                    suffix: "px"
                ),
                ParameterDefinition(
                    key: "height",
                    name: "Height",
                    type: .number,
                    required: false,
                    description: "Window height in pixels",
                    validation: ValidationRule(minValue: 0),
                    suffix: "px"
                ),
                ParameterDefinition(
                    key: "width_percent",
                    name: "Width %",
                    type: .number,
                    required: false,
                    description: "Width as percentage of screen",
                    validation: ValidationRule(minValue: 0, maxValue: 100),
                    suffix: "%"
                ),
                ParameterDefinition(
                    key: "height_percent",
                    name: "Height %",
                    type: .number,
                    required: false,
                    description: "Height as percentage of screen",
                    validation: ValidationRule(minValue: 0, maxValue: 100),
                    suffix: "%"
                ),
                ParameterDefinition(
                    key: "maintain_aspect_ratio",
                    name: "Maintain Aspect Ratio",
                    type: .boolean,
                    defaultValue: AnyCodable(false),
                    description: "Keep the current aspect ratio when resizing"
                )
            ],
            icon: "arrow.up.left.and.arrow.down.right"
        ),
        PluginAction(
            id: "set_position",
            name: "Set Window Position",
            description: "Set custom window position",
            requiresParameters: true,
            supportedParameters: windowTargetParameters + [
                ParameterDefinition(
                    key: "position_type",
                    name: "Position Type",
                    type: .selection,
                    defaultValue: AnyCodable("absolute"),
                    description: "How to interpret the position values",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("absolute"),
                        AnyCodable("relative"),
                        AnyCodable("screen_percentage"),
                        AnyCodable("preset")
                    ]),
                    displayValues: [
                        "absolute": "Absolute Position",
                        "relative": "Relative to Current",
                        "screen_percentage": "Screen Percentage",
                        "preset": "Preset Position"
                    ]
                ),
                ParameterDefinition(
                    key: "x",
                    name: "X Position",
                    type: .number,
                    required: false,
                    description: "X coordinate",
                    visibleWhen: ParameterVisibilityRule(key: "position_type", anyOf: ["absolute", "relative", "screen_percentage"])
                ),
                ParameterDefinition(
                    key: "y",
                    name: "Y Position",
                    type: .number,
                    required: false,
                    description: "Y coordinate",
                    visibleWhen: ParameterVisibilityRule(key: "position_type", anyOf: ["absolute", "relative", "screen_percentage"])
                ),
                ParameterDefinition(
                    key: "preset",
                    name: "Preset Position",
                    type: .selection,
                    required: false,
                    description: "Preset position",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("topLeft"),
                        AnyCodable("topCenter"),
                        AnyCodable("topRight"),
                        AnyCodable("middleLeft"),
                        AnyCodable("center"),
                        AnyCodable("middleRight"),
                        AnyCodable("bottomLeft"),
                        AnyCodable("bottomCenter"),
                        AnyCodable("bottomRight")
                    ]),
                    visibleWhen: ParameterVisibilityRule(key: "position_type", value: "preset"),
                    displayValues: [
                        "topLeft": "Top Left",
                        "topCenter": "Top Center",
                        "topRight": "Top Right",
                        "middleLeft": "Middle Left",
                        "center": "Center",
                        "middleRight": "Middle Right",
                        "bottomLeft": "Bottom Left",
                        "bottomCenter": "Bottom Center",
                        "bottomRight": "Bottom Right"
                    ]
                )
            ],
            icon: "arrow.up.and.down.and.arrow.left.and.right"
        ),

        // MARK: Moved from Core: app/window arrangement actions
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
        PluginAction(
            id: "cycle_space",
            name: "Cycle Space",
            description: "Move to the next, previous, or a specific desktop space",
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
                        AnyCodable("previous"),
                        AnyCodable("specific")
                    ]),
                    displayValues: ["next": "Next", "previous": "Previous", "specific": "Specific Space"]
                ),
                ParameterDefinition(
                    key: "space_number",
                    name: "Space Number",
                    type: .number,
                    defaultValue: AnyCodable(1),
                    description: "Which desktop space to switch to, numbered as shown in Mission Control",
                    validation: ValidationRule(minValue: 1, maxValue: 16),
                    visibleWhen: ParameterVisibilityRule(key: "direction", value: "specific")
                )
            ],
            supportsRepeat: true,
            icon: "arrow.right.square"
        )
    ]

    // MARK: - Plugin Lifecycle

    private var context: PluginContext?

    func initialize(context: PluginContext) throws {
        self.context = context
        loadSavedPositions(context: context)
        loadLayoutsFromDisk(context: context)
        context.logger.log("Window Management Plugin initialized", file: #file, function: #function, line: #line)
    }

    func cleanup() {
        context?.logger.log("Window Management Plugin cleaned up", file: #file, function: #function, line: #line)
        context = nil
    }

    // MARK: - Action Execution

    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        let target = parseWindowTarget(from: parameters)

        switch action.id {

        // MARK: Window Controls (moved from Core)
        case "close_window":
            let closeTargets = getTargetWindows(target, context: context)
            if closeTargets.isEmpty {
                context.sendKeyboardShortcut(keyCode: 13, modifiers: [.maskCommand])
            } else {
                for (window, _) in closeTargets {
                    if let btnObj = context.getAccessibilityAttribute(window, attribute: kAXCloseButtonAttribute as String),
                       CFGetTypeID(btnObj) == AXUIElementGetTypeID() {
                        _ = context.performAccessibilityAction(unsafeBitCast(btnObj, to: AXUIElement.self), action: kAXPressAction as String)
                    }
                }
            }

        case "minimize":
            let minimizeTargets = getTargetWindows(target, context: context)
            if minimizeTargets.isEmpty {
                context.sendKeyboardShortcut(keyCode: 46, modifiers: [.maskCommand])
            } else {
                for (window, _) in minimizeTargets {
                    _ = context.setAccessibilityAttribute(window, attribute: kAXMinimizedAttribute as String, value: true as CFBoolean)
                }
            }

        case "maximize":
            for (window, _) in getTargetWindows(target, context: context) {
                let screen = getScreenForWindow(window, context: context) ?? NSScreen.main
                guard let sf = screen?.visibleFrame else { continue }
                var origin = CGPoint(x: sf.minX, y: sf.minY)
                var size   = CGSize(width: sf.width, height: sf.height)
                if let p = AXValueCreate(.cgPoint, &origin) { _ = context.setAccessibilityAttribute(window, attribute: kAXPositionAttribute as String, value: p) }
                if let s = AXValueCreate(.cgSize, &size) { _ = context.setAccessibilityAttribute(window, attribute: kAXSizeAttribute  as String, value: s) }
            }

        case "fullscreen":
            let fsTargets = getTargetWindows(target, context: context)
            if fsTargets.isEmpty {
                context.sendKeyboardShortcut(keyCode: 3, modifiers: [.maskControl, .maskCommand])
            } else {
                for (window, _) in fsTargets {
                    // Try AX full-screen button; fall back to Cmd+Ctrl+F if absent or if press fails
                    var pressed = false
                    if let btnObj = context.getAccessibilityAttribute(window, attribute: "AXFullScreenButton"),
                       CFGetTypeID(btnObj) == AXUIElementGetTypeID() {
                        let btn = unsafeBitCast(btnObj, to: AXUIElement.self)
                        pressed = context.performAccessibilityAction(btn, action: kAXPressAction as String)
                    }
                    if !pressed {
                        context.sendKeyboardShortcut(keyCode: 3, modifiers: [.maskControl, .maskCommand])
                    }
                }
            }

        // MARK: Move to Display
        case "move_to_display":
            let displayParam = parameters.string(for: "display") ?? "next"
            moveToDisplay(displayParam, target: target, context: context)

        // MARK: Snap Window
        case "snap_window":
            let position = parameters.string(for: "position") ?? "left_half"
            snapWindow(to: position, target: target, context: context)

        // MARK: Resize
        case "resize_to_percent":
            let percent = parameters.number(for: "percent") ?? 50
            resizeToPercent(percent, target: target, context: context)

        case "adjust_size":
            let direction = parameters.string(for: "direction") ?? "grow"
            let unit = parameters.string(for: "unit") ?? "percent"
            if unit == "pixels" {
                let px = CGFloat(parameters.number(for: "pixels") ?? 50)
                let delta = direction == "grow" ? px : -px
                let msg = direction == "grow" ? "Grew window by \(Int(px))px" : "Shrank window by \(Int(px))px"
                resizeWindowByPixels(delta, target: target, logMessage: msg, context: context)
            } else {
                let percent = parameters.number(for: "percent") ?? 10
                let factor: CGFloat = direction == "grow"
                    ? 1.0 + (percent / 100.0)
                    : 1.0 - (percent / 100.0)
                let msg = direction == "grow" ? "Grew window by \(Int(percent))%" : "Shrank window by \(Int(percent))%"
                resizeWindowByFactor(factor, target: target, logMessage: msg, context: context)
            }

        // MARK: Window Navigation
        case "switch_to_window":
            switchToWindow(target: target, context: context)

        // MARK: Position Memory
        case "window_position_memory":
            let operation = parameters.string(for: "operation") ?? "save"
            let slot = parameters.string(for: "slot")
            switch operation {
            case "save":
                saveCurrentWindowPosition(target: target, slot: slot, context: context)
            case "restore":
                restoreWindowPosition(target: target, slot: slot, context: context)
            case "delete":
                deleteWindowPosition(target: target, slot: slot, context: context)
            default:
                break
            }

        // MARK: Layouts
        case "window_layout":
            let operation = parameters.string(for: "operation") ?? "save"
            guard let name = parameters.string(for: "layout_name") else { break }
            switch operation {
            case "save":
                saveWindowLayout(name: name, context: context)
            case "restore":
                let reopenApps = parameters.bool(for: "reopen_apps") ?? true
                restoreWindowLayout(name: name, reopenApps: reopenApps, context: context)
            case "delete":
                deleteLayout(named: name)
            default:
                break
            }

        // MARK: Tile / Cascade
        case "tile_all":
            let tileScope = parameters.string(for: "scope") ?? "current_app"
            let tileResize = parameters.bool(for: "resize_windows") ?? true
            let tileConstant = parameters.bool(for: "constant_size") ?? false
            let tileWidth = parameters.number(for: "tile_width").map { CGFloat($0) }
            let tileHeight = parameters.number(for: "tile_height").map { CGFloat($0) }
            let tileTarget: WindowTargeting.WindowTarget?
            switch tileScope {
            case "all_windows":
                var t = WindowTargeting.WindowTarget(); t.targetType = .allWindows; tileTarget = t
            case "specific_app":
                var t = WindowTargeting.WindowTarget()
                t.targetType = .allWindowsOfApp
                t.applicationBundleId = parameters.string(for: "tile_app_bundle_id")
                tileTarget = t
            default:
                tileTarget = target
            }
            tileAllWindows(target: tileTarget, resize: tileResize, constantSize: tileConstant, fixedWidth: tileWidth, fixedHeight: tileHeight, context: context)
        case "cascade":
            let cascadeScope = parameters.string(for: "scope") ?? "current_app"
            let resizeWindows = parameters.bool(for: "resize_windows") ?? true
            if cascadeScope == "all_windows" {
                var allTarget = WindowTargeting.WindowTarget()
                allTarget.targetType = .allWindows
                cascadeWindows(target: allTarget, resize: resizeWindows, context: context)
            } else {
                cascadeWindows(target: nil, resize: resizeWindows, context: context)
            }

        // MARK: Custom Size / Position
        case "set_size":
            let params = WindowSizeParameters(
                width: parameters.number(for: "width").map { Int($0) },
                height: parameters.number(for: "height").map { Int($0) },
                widthPercent: parameters.number(for: "width_percent").map { Int($0) },
                heightPercent: parameters.number(for: "height_percent").map { Int($0) },
                maintainAspectRatio: parameters.bool(for: "maintain_aspect_ratio") ?? false
            )
            setWindowSize(params: params, target: target, context: context)

        case "set_position":
            let positionTypeStr = parameters.string(for: "position_type") ?? "absolute"
            let positionType: WindowPositionParameters.PositionType
            switch positionTypeStr {
            case "relative":          positionType = .relative
            case "screen_percentage": positionType = .screenPercentage
            case "preset":            positionType = .preset
            default:                  positionType = .absolute
            }

            var preset: WindowPositionParameters.PresetPosition? = nil
            if let presetStr = parameters.string(for: "preset") {
                let formatted = presetStr
                    .replacingOccurrences(of: "topLeft", with: "Top Left")
                    .replacingOccurrences(of: "topCenter", with: "Top Center")
                    .replacingOccurrences(of: "topRight", with: "Top Right")
                    .replacingOccurrences(of: "middleLeft", with: "Middle Left")
                    .replacingOccurrences(of: "center", with: "Center")
                    .replacingOccurrences(of: "middleRight", with: "Middle Right")
                    .replacingOccurrences(of: "bottomLeft", with: "Bottom Left")
                    .replacingOccurrences(of: "bottomCenter", with: "Bottom Center")
                    .replacingOccurrences(of: "bottomRight", with: "Bottom Right")
                preset = WindowPositionParameters.PresetPosition(rawValue: formatted)
            }

            let params = WindowPositionParameters(
                positionType: positionType,
                x: parameters.number(for: "x").map { Int($0) },
                y: parameters.number(for: "y").map { Int($0) },
                xPercent: positionType == .screenPercentage ? parameters.number(for: "x").map { Int($0) } : nil,
                yPercent: positionType == .screenPercentage ? parameters.number(for: "y").map { Int($0) } : nil,
                preset: preset
            )
            setWindowPosition(params: params, target: target, context: context)

        // MARK: Moved from Core: app/window arrangement actions
        case "hide_app":
            let hideTarget = parameters.string(for: "target") ?? "frontmost"
            let hideBundleId = parameters.string(for: "app_bundle_id")
            hideApplication(target: hideTarget, bundleId: hideBundleId, context: context)

        case "quit_app":
            let quitTarget = parameters.string(for: "target") ?? "frontmost"
            let quitBundleId = parameters.string(for: "app_bundle_id")
            quitApplication(target: quitTarget, bundleId: quitBundleId, context: context)

        case "mission_control":
            activateMissionControl(context: context)
        case "show_desktop":
            showDesktop(context: context)
        case "app_expose":
            activateAppExpose(context: context)

        case "cycle_window":
            let cycleForward = (parameters.string(for: "direction") ?? "forward") == "forward"
            let cycleScope = parameters.string(for: "scope") ?? "current"
            if cycleScope == "all_apps" {
                cycleAcrossAllWindows(forward: cycleForward, context: context)
            } else {
                let appBundleId = cycleScope == "specific" ? parameters.string(for: "app_bundle_id") : nil
                cycleWindows(forward: cycleForward, appBundleId: appBundleId, context: context)
            }

        case "cycle_space":
            let direction = parameters.string(for: "direction") ?? "next"
            if direction == "specific" {
                let spaceNumber = Int(parameters.number(for: "space_number") ?? 1)
                moveToSpace(atPosition: spaceNumber, context: context)
            } else {
                moveToSpace(next: direction == "next", context: context)
            }

        default:
            throw PluginError.actionNotFound(action.id)
        }
    }

    func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        switch action.id {
        case "snap_window":
            if parameters.string(for: "position") == nil {
                return .invalid(error: "A position is required")
            }

        case "resize_to_percent":
            guard let pct = parameters.number(for: "percent"), pct >= 1, pct <= 100 else {
                return .invalid(error: "Percent must be between 1 and 100")
            }

        case "window_layout":
            if parameters.string(for: "layout_name") == nil {
                return .invalid(error: "Layout name is required")
            }

        case "set_size":
            let hasWidth        = parameters.number(for: "width") != nil
            let hasHeight       = parameters.number(for: "height") != nil
            let hasWidthPct     = parameters.number(for: "width_percent") != nil
            let hasHeightPct    = parameters.number(for: "height_percent") != nil
            if !hasWidth && !hasHeight && !hasWidthPct && !hasHeightPct {
                return .invalid(error: "At least one size parameter is required")
            }

        case "set_position":
            let positionType = parameters.string(for: "position_type") ?? "absolute"
            switch positionType {
            case "preset":
                if parameters.string(for: "preset") == nil {
                    return .invalid(error: "Preset position is required when using preset type")
                }
            case "absolute", "relative", "screen_percentage":
                if parameters.number(for: "x") == nil && parameters.number(for: "y") == nil {
                    return .invalid(error: "At least one coordinate (X or Y) is required")
                }
            default:
                break
            }

        default:
            if let targetType = parameters.string(for: "target") {
                switch targetType {
                case "by_application", "all_in_app":
                    if parameters.string(for: "app_bundle_id") == nil {
                        return .invalid(error: "An application must be specified for this target type")
                    }
                case "by_title", "by_title_contains":
                    if parameters.string(for: "window_title") == nil {
                        return .invalid(error: "Window title is required for this target type")
                    }
                case "by_age":
                    if parameters.number(for: "window_age") == nil {
                        return .invalid(error: "Window age is required for this target type")
                    }
                default:
                    break
                }
            }
        }
        return .valid
    }

    func configurationView(for action: PluginAction) -> NSView? {
        return nil
    }

    // MARK: - Snap Window

    private func snapWindow(to position: String, target: WindowTargeting.WindowTarget?, context: PluginContext) {
        let windows = getTargetWindows(target, context: context)
        guard !windows.isEmpty else { return }

        for (window, pid) in windows {
            guard let screen = getScreenForWindow(window, context: context),
                  let currentFrame = getWindowFrame(window, context: context) else { continue }

            let bundleId = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown"
            let key = "app:\(bundleId)"

            // Snapping to the same position twice IN A ROW undoes the first snap
            // (restores the pre-snap frame) — but ONLY if the window is still where
            // that snap actually put it. If the user has since moved or resized the
            // window away, a repeat snap should re-apply the position, not silently
            // jump back to the old frame. (Previously the toggle fired on a position
            // match alone, so snap → move-it-yourself → snap-again wrongly restored
            // the original frame instead of snapping to the set position.)
            stateLock.lock()
            let previous = lastSnapByApp[key]
            stateLock.unlock()

            if let previous = previous, previous.position == position,
               framesApproximatelyEqual(currentFrame, previous.snappedFrame) {
                setWindowFrame(window, frame: previous.originalFrame, context: context)
                stateLock.lock()
                lastSnapByApp.removeValue(forKey: key)
                stateLock.unlock()
                context.logger.log("Reverted snap-to-\(position); restored previous window position", file: #file, function: #function, line: #line)
                continue
            }

            guard applySnapPosition(position, window: window, currentFrame: currentFrame, screen: screen, context: context) else {
                context.logger.log("Unknown snap position: \(position)", file: #file, function: #function, line: #line)
                continue
            }

            // Record where the snap actually LANDED (read back, not the requested
            // frame — setWindowFrame clamps to a minimum size and the app may
            // constrain it further) so the next repeat can tell whether the window
            // is still snapped there (→ toggle back) or was moved away (→ re-snap).
            let landedFrame = getWindowFrame(window, context: context) ?? currentFrame
            stateLock.lock()
            lastSnapByApp[key] = (position: position, originalFrame: currentFrame, snappedFrame: landedFrame)
            stateLock.unlock()
        }
    }

    /// Applies a single named snap position to one window. Returns false for
    /// an unrecognized position (nothing was moved).
    @discardableResult
    private func applySnapPosition(_ position: String, window: AXUIElement, currentFrame: CGRect, screen: NSScreen, context: PluginContext) -> Bool {
        switch position {
        case "maximize":
            positionWindow(window, relativeTo: screen, x: 0, y: 0, width: 1, height: 1, context: context)
        case "center":
            let sf = screen.visibleFrame
            let newFrame = CGRect(
                x: sf.midX - currentFrame.width / 2,
                y: sf.midY - currentFrame.height / 2,
                width: currentFrame.width,
                height: currentFrame.height
            )
            setWindowFrame(window, frame: newFrame, context: context)
        case "left_half":
            positionWindow(window, relativeTo: screen, x: 0, y: 0, width: 0.5, height: 1, context: context)
        case "right_half":
            positionWindow(window, relativeTo: screen, x: 0.5, y: 0, width: 0.5, height: 1, context: context)
        case "top_half":
            positionWindow(window, relativeTo: screen, x: 0, y: 0, width: 1, height: 0.5, context: context)
        case "bottom_half":
            positionWindow(window, relativeTo: screen, x: 0, y: 0.5, width: 1, height: 0.5, context: context)
        case "top_left":
            positionWindow(window, relativeTo: screen, x: 0, y: 0, width: 0.5, height: 0.5, context: context)
        case "top_right":
            positionWindow(window, relativeTo: screen, x: 0.5, y: 0, width: 0.5, height: 0.5, context: context)
        case "bottom_left":
            positionWindow(window, relativeTo: screen, x: 0, y: 0.5, width: 0.5, height: 0.5, context: context)
        case "bottom_right":
            positionWindow(window, relativeTo: screen, x: 0.5, y: 0.5, width: 0.5, height: 0.5, context: context)
        case "left_third":
            positionWindow(window, relativeTo: screen, x: 0, y: 0, width: 1.0 / 3.0, height: 1, context: context)
        case "center_third":
            positionWindow(window, relativeTo: screen, x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1, context: context)
        case "right_third":
            positionWindow(window, relativeTo: screen, x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1, context: context)
        default:
            return false
        }
        return true
    }

    /// Two frames are "the same place" (for snap-toggle detection) when every
    /// edge is within `tolerance` points. Absorbs sub-pixel AX rounding and the
    /// min-size clamp while still treating any real user move/resize as a change.
    private func framesApproximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 8) -> Bool {
        return abs(a.origin.x - b.origin.x) <= tolerance &&
               abs(a.origin.y - b.origin.y) <= tolerance &&
               abs(a.size.width - b.size.width) <= tolerance &&
               abs(a.size.height - b.size.height) <= tolerance
    }

    // MARK: - Core Window Management Functions

    private func getTargetWindow(_ target: WindowTargeting.WindowTarget?, context: PluginContext) -> (AXUIElement, pid_t)? {
        let actualTarget = target ?? WindowTargeting.WindowTarget(targetType: .frontmost)
        let params = targetToParams(actualTarget)
        return context.getTargetWindow(params)
    }

    private func getTargetWindows(_ target: WindowTargeting.WindowTarget?, context: PluginContext) -> [(AXUIElement, pid_t)] {
        let actualTarget = target ?? WindowTargeting.WindowTarget(targetType: .frontmost)
        let params = targetToParams(actualTarget)
        return context.getTargetWindows(params)
    }

    private func targetToParams(_ target: WindowTargeting.WindowTarget) -> [String: Any] {
        var params: [String: Any] = [:]
        params["targetType"] = target.targetType.rawValue
        if let bundleId = target.applicationBundleId { params["bundleId"] = bundleId }
        if let title = target.windowTitle { params["windowTitle"] = title }
        if let titleContains = target.windowTitleContains { params["windowTitleContains"] = titleContains }
        if let age = target.windowAge { params["windowAge"] = age }
        return params
    }

    private func getWindowFrame(_ window: AXUIElement, context: PluginContext) -> CGRect? {
        guard let positionValue = context.getAccessibilityAttribute(window, attribute: kAXPositionAttribute as String),
              let sizeValue = context.getAccessibilityAttribute(window, attribute: kAXSizeAttribute as String) else {
            return nil
        }
        // getAccessibilityAttribute hands back an opaque CFTypeRef; a
        // misbehaving app can return something that is not an AXValue, which
        // would make `as! AXValue` trap. Verify the CF type first (same guard
        // as ActionExecutionManager.getSelectedText).
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private func setWindowFrame(_ window: AXUIElement, frame: CGRect, context: PluginContext) {
        var position = frame.origin
        var size = frame.size
        size.width  = max(size.width, 200)
        size.height = max(size.height, 150)
        if let positionValue = AXValueCreate(.cgPoint, &position),
           let sizeValue = AXValueCreate(.cgSize, &size) {
            let posResult  = context.setAccessibilityAttribute(window, attribute: kAXPositionAttribute as String, value: positionValue)
            let sizeResult = context.setAccessibilityAttribute(window, attribute: kAXSizeAttribute as String, value: sizeValue)
            if !posResult || !sizeResult {
                context.logger.log("Failed to set window frame", file: #file, function: #function, line: #line)
            }
        }
    }

    private func getScreenForWindow(_ window: AXUIElement, context: PluginContext) -> NSScreen? {
        guard let frame = getWindowFrame(window, context: context) else { return NSScreen.main }
        // getWindowFrame returns AX coordinates (origin top-left of the primary
        // screen, Y increasing downward); NSScreen.frame is Cocoa coordinates
        // (origin bottom-left of the primary screen, Y increasing upward).
        // Convert before comparing — the same flip tileAllWindows/
        // setWindowPositionSingle already apply in the opposite direction.
        // Comparing raw AX Y against Cocoa frames happens to still work on
        // the primary screen (both fall in the same [0, primaryH] band) but
        // silently picks the wrong display for any window off the primary
        // screen.
        let primaryH = NSScreen.screens.first?.frame.height ?? frame.height
        let cocoaFrame = CGRect(x: frame.minX, y: primaryH - frame.maxY, width: frame.width, height: frame.height)
        for screen in NSScreen.screens {
            if screen.frame.contains(CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)) { return screen }
        }
        var bestScreen = NSScreen.main
        var maxOverlap: CGFloat = 0
        for screen in NSScreen.screens {
            let overlap = screen.frame.intersection(cocoaFrame).width * screen.frame.intersection(cocoaFrame).height
            if overlap > maxOverlap { maxOverlap = overlap; bestScreen = screen }
        }
        return bestScreen
    }

    // MARK: - Positioning Helpers

    private func positionWindow(_ window: AXUIElement, relativeTo screen: NSScreen, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, context: PluginContext) {
        let frame = screen.visibleFrame
        // AX y-origin of this screen's visible area = primaryScreenHeight -
        // frame.maxY (same conversion as tileAllWindows/setWindowPositionSingle).
        // The old `NSStatusBar.system.thickness` constant is only correct on
        // the primary screen (it happens to equal this formula's result
        // there); on a secondary screen it produced the wrong Y, so
        // snap-to-region misplaced windows vertically on any non-primary
        // display.
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let axTopY = primaryH - frame.maxY
        let newFrame = CGRect(
            x: frame.minX + x * frame.width,
            y: axTopY + y * frame.height,
            width: width * frame.width,
            height: height * frame.height
        )
        setWindowFrame(window, frame: newFrame, context: context)
    }

    // MARK: - Sizing

    private func resizeToPercent(_ percent: CGFloat, target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        let windows = getTargetWindows(target, context: context)
        for (window, _) in windows {
            guard let screen = getScreenForWindow(window, context: context) else { continue }
            let sf    = screen.visibleFrame
            let scale = percent / 100.0
            let w     = sf.width * scale
            let h     = sf.height * scale
            let newFrame = CGRect(x: sf.midX - w / 2, y: sf.midY - h / 2, width: w, height: h)
            setWindowFrame(window, frame: newFrame, context: context)
        }
        context.logger.log("Resized \(windows.count) window(s) to \(Int(percent))%", file: #file, function: #function, line: #line)
    }

    private func resizeWindowByFactor(_ factor: CGFloat, target: WindowTargeting.WindowTarget?, logMessage: String, context: PluginContext) {
        let windows = getTargetWindows(target, context: context)
        for (window, _) in windows {
            guard let currentFrame = getWindowFrame(window, context: context) else { continue }
            let nw = currentFrame.width * factor
            let nh = currentFrame.height * factor
            let newFrame = CGRect(x: currentFrame.origin.x, y: currentFrame.origin.y, width: nw, height: nh)
            setWindowFrame(window, frame: newFrame, context: context)
        }
        context.logger.log(logMessage, file: #file, function: #function, line: #line)
    }

    private func moveToDisplay(_ displayParam: String, target: WindowTargeting.WindowTarget?, context: PluginContext) {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            context.logger.log("move_to_display: only one display found", file: #file, function: #function, line: #line)
            return
        }
        for (window, _) in getTargetWindows(target, context: context) {
            guard let currentScreen = getScreenForWindow(window, context: context),
                  let currentFrame  = getWindowFrame(window, context: context) else { continue }

            let currentIdx = screens.firstIndex(of: currentScreen) ?? 0
            let targetScreen: NSScreen?
            switch displayParam {
            case "next":
                targetScreen = screens[(currentIdx + 1) % screens.count]
            case "previous":
                targetScreen = screens[(currentIdx - 1 + screens.count) % screens.count]
            default:
                if let idx = Int(displayParam), idx >= 1 && idx <= screens.count {
                    targetScreen = screens[idx - 1]
                } else {
                    targetScreen = nil
                }
            }
            guard let dst = targetScreen, dst != currentScreen else { continue }

            // Translate window position proportionally to the new screen
            let src = currentScreen.visibleFrame
            let dstF = dst.visibleFrame
            let xRatio = (currentFrame.minX - src.minX) / src.width
            let yRatio = (currentFrame.minY - src.minY) / src.height
            let newOrigin = CGPoint(
                x: dstF.minX + xRatio * dstF.width,
                y: dstF.minY + yRatio * dstF.height
            )
            // Clamp size so window fits on destination screen
            let newSize = CGSize(
                width: min(currentFrame.width, dstF.width),
                height: min(currentFrame.height, dstF.height)
            )
            var o = newOrigin; var s = newSize
            if let pv = AXValueCreate(.cgPoint, &o) { _ = context.setAccessibilityAttribute(window, attribute: kAXPositionAttribute as String, value: pv) }
            if let sv = AXValueCreate(.cgSize, &s) { _ = context.setAccessibilityAttribute(window, attribute: kAXSizeAttribute  as String, value: sv) }
        }
        context.logger.log("Moved window(s) to display: \(displayParam)", file: #file, function: #function, line: #line)
    }

    private func resizeWindowByPixels(_ delta: CGFloat, target: WindowTargeting.WindowTarget?, logMessage: String, context: PluginContext) {
        let windows = getTargetWindows(target, context: context)
        for (window, _) in windows {
            guard let currentFrame = getWindowFrame(window, context: context) else { continue }
            let nw = max(100, currentFrame.width + delta)
            let nh = max(100, currentFrame.height + delta)
            let newFrame = CGRect(x: currentFrame.origin.x, y: currentFrame.origin.y, width: nw, height: nh)
            setWindowFrame(window, frame: newFrame, context: context)
        }
        context.logger.log(logMessage, file: #file, function: #function, line: #line)
    }

    // MARK: - Window Navigation

    private func switchToWindow(target: WindowTargeting.WindowTarget?, context: PluginContext) {
        guard let target = target,
              let (window, pid) = getTargetWindow(target, context: context) else { return }
        // Activate the app so it comes to front
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        let result = context.performAccessibilityAction(window, action: kAXRaiseAction as String)
        context.logger.log(result ? "Switched to target window" : "Failed to switch to window", file: #file, function: #function, line: #line)
    }

    // MARK: - Advanced Window Management

    private func getAppWindows(target: WindowTargeting.WindowTarget?, context: PluginContext) -> [AXUIElement] {
        if let target = target {
            switch target.targetType {
            case .allWindowsOfApp:
                return context.getAllVisibleWindows().filter { (_, pid) in
                    if let bundleId = target.applicationBundleId,
                       let app = NSRunningApplication(processIdentifier: pid) {
                        return app.bundleIdentifier == bundleId
                    }
                    return false
                }.map { $0.0 }
            case .allWindows:
                return context.getAllVisibleWindows().map { $0.window }
            default:
                break
            }
        }
        guard let frontApp = context.getFrontmostApplication() else { return [] }
        return context.getWindowsForApplication(frontApp.processIdentifier)
    }

    /// Bundle ID prefixes for desktop widgets that should be excluded from tiling and cascading
    private static let widgetBundlePrefixes = ["com.apple.notificationcenterui", "com.apple.WidgetKit"]

    /// Filter out desktop widget windows
    private func filterOutWidgets(_ windows: [AXUIElement], context: PluginContext) -> [AXUIElement] {
        return windows.filter { window in
            var pid: pid_t = 0
            AXUIElementGetPid(window, &pid)
            guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
            // Exclude non-regular apps (widgets, menu bar apps, etc.)
            guard app.activationPolicy == .regular else { return false }
            // Exclude known widget bundle prefixes
            if let bundleId = app.bundleIdentifier {
                if Self.widgetBundlePrefixes.contains(where: { bundleId.hasPrefix($0) }) { return false }
            }
            // Exclude windows with zero or very small size
            if let frame = getWindowFrame(window, context: context) {
                if frame.width < 50 || frame.height < 50 { return false }
            }
            return true
        }
    }

    private func tileAllWindows(target: WindowTargeting.WindowTarget? = nil, resize: Bool = true, constantSize: Bool = false, fixedWidth: CGFloat? = nil, fixedHeight: CGFloat? = nil, context: PluginContext) {
        let rawWindows = getAppWindows(target: target, context: context)
        let windows = filterOutWidgets(rawWindows, context: context)
        guard !windows.isEmpty, let screen = NSScreen.main else { return }
        let sf  = screen.visibleFrame
        let cnt = windows.count

        if constantSize, let fw = fixedWidth, let fh = fixedHeight {
            // Fixed-size tiling: arrange windows in a grid at fixed size
            let cols = max(1, Int(sf.width / fw))
            let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let axTopY = primaryH - sf.maxY
            for (idx, window) in windows.enumerated() {
                let col = idx % cols
                let row = idx / cols
                let x = sf.minX + CGFloat(col) * fw
                let y = axTopY + CGFloat(row) * fh
                setWindowFrame(window, frame: CGRect(x: x, y: y, width: fw, height: fh), context: context)
            }
            context.logger.log("Tiled \(cnt) windows at \(Int(fw))x\(Int(fh))", file: #file, function: #function, line: #line)
            return
        }

        // Calculate optimal grid layout that minimizes wasted space
        // Try different column counts and pick the one with the best aspect ratio fit
        var bestCols = 1
        var bestScore = CGFloat.infinity
        let screenRatio = sf.width / sf.height

        for cols in 1...cnt {
            let rows = Int(ceil(Double(cnt) / Double(cols)))
            let cellW = sf.width / CGFloat(cols)
            let cellH = sf.height / CGFloat(rows)
            let cellRatio = cellW / cellH
            // Prefer layouts where cells have similar aspect ratio to screen
            // and minimize empty cells in the last row
            let ratioScore = abs(cellRatio - screenRatio)
            let wasteScore = CGFloat(cols * rows - cnt) / CGFloat(cnt) * 0.5
            let score = ratioScore + wasteScore
            if score < bestScore {
                bestScore = score
                bestCols = cols
            }
        }

        let cols = bestCols
        let rows = Int(ceil(Double(cnt) / Double(cols)))
        let lastRowCols = cnt - (rows - 1) * cols

        for (idx, window) in windows.enumerated() {
            let row = idx / cols
            let col = idx % cols
            let isLastRow = row == rows - 1

            // Center the last row if it has fewer windows
            let effectiveCols = isLastRow ? lastRowCols : cols
            let effectiveCol = isLastRow ? (idx - (rows - 1) * cols) : col
            let winW = sf.width / CGFloat(effectiveCols)
            let winH = sf.height / CGFloat(rows)
            // Convert: AX y-origin of visible area = primaryScreenHeight - sf.maxY
            let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let axTopY = primaryH - sf.maxY
            let origin = CGPoint(
                x: sf.minX + CGFloat(effectiveCol) * winW,
                y: axTopY + CGFloat(row) * winH
            )
            if resize {
                setWindowFrame(window, frame: CGRect(origin: origin, size: CGSize(width: winW, height: winH)), context: context)
            } else {
                // Move only — keep existing size
                if var f = getWindowFrame(window, context: context) {
                    f.origin = origin
                    setWindowFrame(window, frame: f, context: context)
                }
            }
        }
        context.logger.log("Tiled \(cnt) windows in \(cols)x\(rows) grid", file: #file, function: #function, line: #line)
    }

    private func cascadeWindows(target: WindowTargeting.WindowTarget? = nil, resize: Bool = true, context: PluginContext) {
        let rawWindows = getAppWindows(target: target, context: context)
        let windows = filterOutWidgets(rawWindows, context: context)
        guard !windows.isEmpty, let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let offset: CGFloat = 30
        let winSize = CGSize(width: sf.width * 0.6, height: sf.height * 0.6)
        // Top of visible area in AX coordinates (below menu bar)
        let topY = NSStatusBar.system.thickness

        // Maximum cascade offset before wrapping to a new stack
        let effectiveWidth = resize ? winSize.width : (windows.compactMap { getWindowFrame($0, context: context)?.width }.max() ?? winSize.width)
        let effectiveHeight = resize ? winSize.height : (windows.compactMap { getWindowFrame($0, context: context)?.height }.max() ?? winSize.height)
        let maxOffset = max(offset, min(sf.width - effectiveWidth, sf.height - effectiveHeight))

        // How many windows fit in one cascade stack
        let windowsPerStack = max(1, Int(maxOffset / offset))
        // Stagger offset for subsequent stacks so all title bars remain visible.
        // Each new stack shifts by half the cascade step, ensuring the previous
        // stack's title bars peek out from behind the new stack.
        let stackStagger = offset / 2.0

        // Reverse offset so the last-placed window (visually frontmost) is at top-left
        let count = windows.count
        for (idx, window) in windows.enumerated() {
            let reverseIdx = count - 1 - idx
            let stackIndex = reverseIdx / windowsPerStack
            let posInStack = reverseIdx % windowsPerStack
            let off = CGFloat(posInStack) * offset + CGFloat(stackIndex) * stackStagger

            if resize {
                let frame = CGRect(
                    x: sf.minX + off,
                    y: topY + off,
                    width: winSize.width, height: winSize.height
                )
                setWindowFrame(window, frame: frame, context: context)
            } else {
                // Only reposition, keep existing size
                if let currentFrame = getWindowFrame(window, context: context) {
                    let frame = CGRect(
                        x: sf.minX + off,
                        y: topY + off,
                        width: currentFrame.width, height: currentFrame.height
                    )
                    setWindowFrame(window, frame: frame, context: context)
                }
            }
        }
        context.logger.log("Cascaded \(windows.count) windows\(resize ? "" : " (no resize)")", file: #file, function: #function, line: #line)
    }

    // MARK: - Window Position Memory

    /// Returns the storage key for a position slot. If `slot` is provided it is used directly;
    /// otherwise the app bundle ID of the targeted window is used.
    private func positionKey(target: WindowTargeting.WindowTarget?, slot: String?, context: PluginContext) -> String? {
        if let slot = slot, !slot.isEmpty, slot != "default" {
            return "slot:\(slot)"
        }
        guard let (_, pid) = getTargetWindow(target, context: context),
              let bundleId = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        return "app:\(bundleId)"
    }

    private func saveCurrentWindowPosition(target: WindowTargeting.WindowTarget? = nil, slot: String?, context: PluginContext) {
        guard let (window, pid) = getTargetWindow(target, context: context),
              let frame = getWindowFrame(window, context: context) else { return }
        let app = NSRunningApplication(processIdentifier: pid)
        let bundleId = app?.bundleIdentifier ?? "unknown"
        let key = slot.map { "slot:\($0)" } ?? "app:\(bundleId)"
        stateLock.lock()
        savedWindowPositions[key] = WindowPosition(
            x: frame.origin.x, y: frame.origin.y,
            width: frame.size.width, height: frame.size.height,
            appIdentifier: bundleId
        )
        stateLock.unlock()
        saveSavedPositions()
        context.logger.log("Saved window position [\(key)]", file: #file, function: #function, line: #line)
    }

    private func restoreWindowPosition(target: WindowTargeting.WindowTarget? = nil, slot: String?, context: PluginContext) {
        guard let (window, pid) = getTargetWindow(target, context: context) else { return }
        let app = NSRunningApplication(processIdentifier: pid)
        let bundleId = app?.bundleIdentifier ?? "unknown"
        let key = slot.map { "slot:\($0)" } ?? "app:\(bundleId)"
        stateLock.lock()
        let saved = savedWindowPositions[key]
        stateLock.unlock()
        guard let saved = saved else {
            context.logger.log("No saved position for key: \(key)", file: #file, function: #function, line: #line)
            return
        }
        setWindowFrame(window, frame: CGRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height), context: context)
        context.logger.log("Restored window position [\(key)]", file: #file, function: #function, line: #line)
    }

    private func deleteWindowPosition(target: WindowTargeting.WindowTarget? = nil, slot: String?, context: PluginContext) {
        guard let (_, pid) = getTargetWindow(target, context: context) else { return }
        let bundleId = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown"
        let key = slot.map { "slot:\($0)" } ?? "app:\(bundleId)"
        stateLock.lock()
        savedWindowPositions.removeValue(forKey: key)
        stateLock.unlock()
        saveSavedPositions()
        context.logger.log("Deleted saved position [\(key)]", file: #file, function: #function, line: #line)
    }

    // MARK: - Window Layouts

    func getAvailableLayouts() -> [String] {
        stateLock.lock(); defer { stateLock.unlock() }
        return Array(savedLayouts.keys).sorted()
    }

    func getAvailablePositionSlots() -> [String] {
        stateLock.lock()
        let keys = Array(savedWindowPositions.keys)
        stateLock.unlock()
        return keys
            .filter { $0.hasPrefix("slot:") }
            .map { String($0.dropFirst("slot:".count)) }
            .sorted()
    }

    func hasLayout(named name: String) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return savedLayouts[name] != nil
    }

    func deleteLayout(named name: String) {
        stateLock.lock()
        savedLayouts.removeValue(forKey: name)
        stateLock.unlock()
        saveLayoutsToDisk()
        context?.logger.log("Deleted window layout: \(name)", file: #file, function: #function, line: #line)
    }

    private func saveWindowLayout(name: String, context: PluginContext) {
        var windowInfos: [WindowLayout.WindowInfo] = []
        for winInfo in context.getAllVisibleWindows() {
            guard let frame = getWindowFrame(winInfo.window, context: context) else { continue }
            let app = NSRunningApplication(processIdentifier: winInfo.pid)
            guard let bundleId = app?.bundleIdentifier else { continue }
            var windowTitle: String?
            if let tv = context.getAccessibilityAttribute(winInfo.window, attribute: kAXTitleAttribute as String) {
                windowTitle = tv as? String
            }
            var isMinimized = false
            if let mv = context.getAccessibilityAttribute(winInfo.window, attribute: kAXMinimizedAttribute as String) {
                isMinimized = (mv as? Bool) ?? false
            }
            windowInfos.append(WindowLayout.WindowInfo(
                appBundleIdentifier: bundleId,
                appName: app?.localizedName ?? "Unknown",
                windowTitle: windowTitle,
                position: frame.origin,
                size: frame.size,
                isMinimized: isMinimized,
                spaceNumber: nil
            ))
        }
        stateLock.lock()
        savedLayouts[name] = WindowLayout(name: name, windows: windowInfos)
        stateLock.unlock()
        saveLayoutsToDisk()
        context.logger.log("Saved layout '\(name)' with \(windowInfos.count) windows", file: #file, function: #function, line: #line)
    }

    private func restoreWindowLayout(name: String, reopenApps: Bool = true, context: PluginContext) {
        stateLock.lock()
        let layout = savedLayouts[name]
        stateLock.unlock()
        guard let layout = layout else {
            context.logger.log("No saved layout: \(name)", file: #file, function: #function, line: #line)
            return
        }
        let windowsByApp = Dictionary(grouping: layout.windows) { $0.appBundleIdentifier }
        for (bundleId, windowInfos) in windowsByApp {
            var app: NSRunningApplication? = context.getRunningApplications().first { $0.bundleIdentifier == bundleId }
            if app == nil && reopenApps {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false
                    let sem = DispatchSemaphore(value: 0)
                    NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { la, _ in app = la; sem.signal() }
                    _ = sem.wait(timeout: .now() + 3.0)
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
            guard let runningApp = app else { continue }
            let appWindows = context.getWindowsForApplication(runningApp.processIdentifier)
            for (idx, info) in windowInfos.enumerated() {
                guard idx < appWindows.count else { break }
                setWindowFrame(appWindows[idx], frame: CGRect(origin: info.position, size: info.size), context: context)
                if info.isMinimized {
                    let min = true as CFBoolean
                    _ = context.setAccessibilityAttribute(appWindows[idx], attribute: kAXMinimizedAttribute as String, value: min)
                }
            }
        }
        context.logger.log("Restored layout '\(name)'", file: #file, function: #function, line: #line)
    }

    // MARK: - Custom Size / Position

    private func setWindowSize(params: WindowSizeParameters, target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        let windows = getTargetWindows(target, context: context)
        for (window, _) in windows { setWindowSizeSingle(window, params: params, context: context) }
        context.logger.log("Set window size: \(params.displayString) (\(windows.count) window(s))", file: #file, function: #function, line: #line)
    }

    private func setWindowSizeSingle(_ window: AXUIElement, params: WindowSizeParameters, context: PluginContext) {
        guard let screen = getScreenForWindow(window, context: context) ?? NSScreen.main,
              let currentFrame = getWindowFrame(window, context: context) else { return }
        let sf = screen.visibleFrame
        var newSize = currentFrame.size
        if let w = params.width { newSize.width  = CGFloat(w) } else if let wp = params.widthPercent { newSize.width  = sf.width * CGFloat(wp) / 100 }
        if let h = params.height { newSize.height = CGFloat(h) } else if let hp = params.heightPercent { newSize.height = sf.height * CGFloat(hp) / 100 }
        if params.maintainAspectRatio {
            let ratio = currentFrame.width / currentFrame.height
            if params.width != nil || params.widthPercent != nil { newSize.height = newSize.width / ratio } else { newSize.width = newSize.height * ratio }
        }
        setWindowFrame(window, frame: CGRect(origin: currentFrame.origin, size: newSize), context: context)
    }

    private func setWindowPosition(params: WindowPositionParameters, target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        let windows = getTargetWindows(target, context: context)
        for (window, _) in windows { setWindowPositionSingle(window, params: params, context: context) }
        context.logger.log("Set window position: \(params.displayString) (\(windows.count) window(s))", file: #file, function: #function, line: #line)
    }

    private func setWindowPositionSingle(_ window: AXUIElement, params: WindowPositionParameters, context: PluginContext) {
        guard let screen = getScreenForWindow(window, context: context) ?? NSScreen.main,
              let currentFrame = getWindowFrame(window, context: context) else { return }
        let sf = screen.visibleFrame
        var newPos = currentFrame.origin
        switch params.positionType {
        case .absolute:
            if let x = params.x { newPos.x = CGFloat(x) }
            if let y = params.y { newPos.y = CGFloat(y) }
        case .relative:
            if let x = params.x { newPos.x += CGFloat(x) }
            if let y = params.y { newPos.y += CGFloat(y) }
        case .screenPercentage:
            if let xp = params.xPercent { newPos.x = sf.minX + sf.width * CGFloat(xp) / 100 }
            if let yp = params.yPercent { newPos.y = sf.minY + sf.height * CGFloat(yp) / 100 }
        case .preset:
            guard let preset = params.preset else { break }
            // Convert NSScreen coords (bottom-left origin) to AX coords (top-left origin)
            let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let axTop = primaryH - sf.maxY       // AX y of top edge of visible area
            let axBottom = primaryH - sf.minY    // AX y of bottom edge of visible area
            let axMid = (axTop + axBottom) / 2   // AX y of vertical center
            let w = currentFrame.width
            let h = currentFrame.height
            switch preset {
            case .topLeft:      newPos = CGPoint(x: sf.minX, y: axTop)
            case .topCenter:    newPos = CGPoint(x: sf.midX - w / 2, y: axTop)
            case .topRight:     newPos = CGPoint(x: sf.maxX - w, y: axTop)
            case .middleLeft:   newPos = CGPoint(x: sf.minX, y: axMid - h / 2)
            case .center:       newPos = CGPoint(x: sf.midX - w / 2, y: axMid - h / 2)
            case .middleRight:  newPos = CGPoint(x: sf.maxX - w, y: axMid - h / 2)
            case .bottomLeft:   newPos = CGPoint(x: sf.minX, y: axBottom - h)
            case .bottomCenter: newPos = CGPoint(x: sf.midX - w / 2, y: axBottom - h)
            case .bottomRight:  newPos = CGPoint(x: sf.maxX - w, y: axBottom - h)
            }
        }
        setWindowFrame(window, frame: CGRect(origin: newPos, size: currentFrame.size), context: context)
    }

    // MARK: - Parse Window Target

    private func parseWindowTarget(from parameters: ActionParameters) -> WindowTargeting.WindowTarget {
        let typeStr = parameters.string(for: "target") ?? "frontmost"
        var target = WindowTargeting.WindowTarget()
        switch typeStr {
        case "frontmost":       target.targetType = .frontmost
        case "by_age":          target.targetType = .byAge;            target.windowAge = parameters.number(for: "window_age").map { Int($0) }
        case "by_application":  target.targetType = .byApplication;    target.applicationBundleId = parameters.string(for: "app_bundle_id")
        case "by_title":        target.targetType = .byWindowTitle;    target.windowTitle = parameters.string(for: "window_title")
        case "by_title_contains": target.targetType = .byWindowTitleContains; target.windowTitleContains = parameters.string(for: "window_title")
        case "all_in_app":      target.targetType = .allWindowsOfApp;  target.applicationBundleId = parameters.string(for: "app_bundle_id")
        case "all_visible":     target.targetType = .allWindows
        case "mouse_position":  target.targetType = .mousePosition
        case "largest":         target.targetType = .largestWindow
        case "smallest":        target.targetType = .smallestWindow
        default:                target.targetType = .frontmost
        }
        // Fallback for missing required data
        switch target.targetType {
        case .byApplication where target.applicationBundleId == nil:     target.targetType = .frontmost
        case .allWindowsOfApp where target.applicationBundleId == nil:   target.targetType = .frontmost
        case .byWindowTitle where target.windowTitle == nil:             target.targetType = .frontmost
        case .byWindowTitleContains where target.windowTitleContains == nil: target.targetType = .frontmost
        case .byAge where target.windowAge == nil:                       target.windowAge = 1
        default: break
        }
        return target
    }

    // MARK: - Persistence

    private func savedPositionsURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("MouseGestures")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("saved_positions.json")
    }

    private func saveSavedPositions() {
        stateLock.lock()
        let snapshot = savedWindowPositions
        stateLock.unlock()
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: savedPositionsURL())
        } catch {
            context?.logger.log("Error saving window positions: \(error)", file: #file, function: #function, line: #line)
        }
    }

    private func loadSavedPositions(context: PluginContext) {
        let url = savedPositionsURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: WindowPosition].self, from: data)
            stateLock.lock()
            savedWindowPositions = decoded
            stateLock.unlock()
        } catch {
            context.logger.log("Error loading saved positions: \(error)", file: #file, function: #function, line: #line)
        }
    }

    private func layoutsURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("MouseGestures")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("window_layouts.json")
    }

    private func saveLayoutsToDisk() {
        stateLock.lock()
        let snapshot = savedLayouts
        stateLock.unlock()
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: layoutsURL())
        } catch {
            context?.logger.log("Error saving window layouts: \(error)", file: #file, function: #function, line: #line)
        }
    }

    private func loadLayoutsFromDisk(context: PluginContext) {
        let url = layoutsURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: WindowLayout].self, from: data)
            stateLock.lock()
            savedLayouts = decoded
            stateLock.unlock()
            context.logger.log("Loaded \(decoded.count) window layouts", file: #file, function: #function, line: #line)
        } catch {
            context.logger.log("Error loading window layouts: \(error)", file: #file, function: #function, line: #line)
        }
    }

    // MARK: - Moved from Core: App/Window Arrangement Implementations

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

    private func quitApplication(target: String, bundleId: String?, context: PluginContext) {
        switch target {
        case "frontmost":
            if let app = context.getFrontmostApplication() {
                if app.bundleIdentifier != "com.apple.finder" {
                    _ = context.terminateApplication(app)
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
        _ = waitForModifierRelease()
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
        _ = waitForModifierRelease()
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
        let allWindows = context.getAllVisibleWindows()
        guard !allWindows.isEmpty else { return }

        // Build per-app map: take the frontmost window of each app
        // Use insertion order from getAllVisibleWindows (z-order: frontmost app first)
        var appMap: [(pid: pid_t, window: AXUIElement)] = []
        var seenPids = Set<pid_t>()
        for (window, pid) in allWindows {
            if seenPids.insert(pid).inserted {
                appMap.append((pid: pid, window: window))
            }
        }
        guard appMap.count > 1 else {
            // Only one app — cycle its own windows using Cmd+`
            if forward {
                context.sendKeyboardShortcut(keyCode: 50, modifiers: [.maskCommand])
            } else {
                context.sendKeyboardShortcut(keyCode: 50, modifiers: [.maskCommand, .maskShift])
            }
            return
        }

        // Sort by PID for stable ordering that doesn't change when windows get focused
        appMap.sort { $0.pid < $1.pid }

        let frontPid = context.getFrontmostApplication()?.processIdentifier ?? 0
        let currentIdx = appMap.firstIndex { $0.pid == frontPid } ?? 0
        let nextIdx = forward
            ? (currentIdx + 1) % appMap.count
            : (currentIdx - 1 + appMap.count) % appMap.count

        let next = appMap[nextIdx]
        if let app = context.getRunningApplications().first(where: { $0.processIdentifier == next.pid }) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        _ = context.performAccessibilityAction(next.window, action: kAXRaiseAction as String)
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
        // Preferred path: jump directly via a hidden per-Space sentinel window
        // (see SpaceSentinelManager) — no keyboard events, so it's immune to
        // physically-held modifiers, and it drives the real click-focus path
        // so the Dock's own Space tracking stays in sync (unlike the earlier,
        // reverted SLSManagedDisplaySetCurrentSpace attempt, which left a
        // broken hybrid state: both menu bars visible, next switch acting on
        // the space the Dock still thought was active).
        //
        // Falls back to key simulation only if the adjacent Space hasn't been
        // visited yet this session (no sentinel there) or the private API is
        // unavailable.
        if SpaceSentinelManager.shared.switchToAdjacentSpace(next: next) { return }
        moveToSpaceViaKeySimulation(keyCode: next ? 124 : 123, context: context)
    }

    private func moveToSpace(atPosition number: Int, context: PluginContext) {
        guard SpaceSentinelManager.shared.switchToSpace(atPosition: number) else {
            // No sentinel for that Space yet (not visited this session) — we
            // can't jump to an arbitrary, non-adjacent Space via key
            // simulation, so there's nothing safe to fall back to.
            context.logger.log("cycle_space: Space \(number) hasn't been visited yet this session, cannot switch to it directly", file: #file, function: #function, line: #line)
            return
        }
    }

    /// System Events is sensitive to physically-held modifiers; wait for all
    /// modifier keys to be released first. This is the fallback path used
    /// only when no sentinel is available for the target Space.
    private func moveToSpaceViaKeySimulation(keyCode: Int, context: PluginContext) {
        _ = waitForModifierRelease()
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
}
