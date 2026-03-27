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
        PluginAction(id: "close_window",   name: "Close Window",      description: "Close a window",           requiresParameters: true, supportedParameters: windowTargetParameters, icon: "xmark.circle"),
        PluginAction(id: "minimize",       name: "Minimize Window",   description: "Minimize a window",        requiresParameters: true, supportedParameters: windowTargetParameters, icon: "minus.circle"),
        PluginAction(id: "maximize",       name: "Maximize Window",   description: "Fill screen (not fullscreen)", requiresParameters: true, supportedParameters: windowTargetParameters, icon: "plus.circle"),
        PluginAction(id: "fullscreen",     name: "Toggle Fullscreen", description: "Toggle fullscreen mode",   requiresParameters: true, supportedParameters: windowTargetParameters, icon: "arrow.up.left.and.arrow.down.right"),

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
                    description: "Resize windows to fill the tiled grid",
                    visibleWhen: ParameterVisibilityRule(key: "constant_size", notValue: "true")
                ),
                ParameterDefinition(
                    key: "constant_size",
                    name: "Constant Size",
                    type: .boolean,
                    defaultValue: AnyCodable(false),
                    description: "Tile each window to a fixed size instead of auto-filling"
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
                    if let btnObj = context.getAccessibilityAttribute(window, attribute: kAXCloseButtonAttribute as String) {
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
                if let s = AXValueCreate(.cgSize,  &size)   { _ = context.setAccessibilityAttribute(window, attribute: kAXSizeAttribute  as String, value: s) }
            }

        case "fullscreen":
            let fsTargets = getTargetWindows(target, context: context)
            if fsTargets.isEmpty {
                context.sendKeyboardShortcut(keyCode: 3, modifiers: [.maskControl, .maskCommand])
            } else {
                for (window, _) in fsTargets {
                    if let btnObj = context.getAccessibilityAttribute(window, attribute: "AXFullScreenButton") {
                        let btn = unsafeBitCast(btnObj, to: AXUIElement.self)
                        _ = context.performAccessibilityAction(btn, action: kAXPressAction as String)
                    } else {
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
        switch position {
        case "maximize":
            positionWindowWithTarget(target: target, x: 0, y: 0, width: 1, height: 1, logMessage: "Snapped window to fill screen", context: context)
        case "center":
            centerWindow(target: target, context: context)
        case "left_half":
            positionWindowWithTarget(target: target, x: 0,       y: 0,   width: 0.5,     height: 1,   logMessage: "Snapped window to left half", context: context)
        case "right_half":
            positionWindowWithTarget(target: target, x: 0.5,     y: 0,   width: 0.5,     height: 1,   logMessage: "Snapped window to right half", context: context)
        case "top_half":
            positionWindowWithTarget(target: target, x: 0,       y: 0,   width: 1,       height: 0.5, logMessage: "Snapped window to top half", context: context)
        case "bottom_half":
            positionWindowWithTarget(target: target, x: 0,       y: 0.5, width: 1,       height: 0.5, logMessage: "Snapped window to bottom half", context: context)
        case "top_left":
            positionWindowWithTarget(target: target, x: 0,       y: 0,   width: 0.5,     height: 0.5, logMessage: "Snapped window to top left", context: context)
        case "top_right":
            positionWindowWithTarget(target: target, x: 0.5,     y: 0,   width: 0.5,     height: 0.5, logMessage: "Snapped window to top right", context: context)
        case "bottom_left":
            positionWindowWithTarget(target: target, x: 0,       y: 0.5, width: 0.5,     height: 0.5, logMessage: "Snapped window to bottom left", context: context)
        case "bottom_right":
            positionWindowWithTarget(target: target, x: 0.5,     y: 0.5, width: 0.5,     height: 0.5, logMessage: "Snapped window to bottom right", context: context)
        case "left_third":
            positionWindowWithTarget(target: target, x: 0,       y: 0,   width: 1.0/3.0, height: 1,   logMessage: "Snapped window to left third", context: context)
        case "center_third":
            positionWindowWithTarget(target: target, x: 1.0/3.0, y: 0,   width: 1.0/3.0, height: 1,   logMessage: "Snapped window to center third", context: context)
        case "right_third":
            positionWindowWithTarget(target: target, x: 2.0/3.0, y: 0,   width: 1.0/3.0, height: 1,   logMessage: "Snapped window to right third", context: context)
        default:
            context.logger.log("Unknown snap position: \(position)", file: #file, function: #function, line: #line)
        }
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
        if let title = target.windowTitle           { params["windowTitle"] = title }
        if let titleContains = target.windowTitleContains { params["windowTitleContains"] = titleContains }
        if let age = target.windowAge               { params["windowAge"] = age }
        return params
    }
    
    private func getWindowFrame(_ window: AXUIElement, context: PluginContext) -> CGRect? {
        guard let positionValue = context.getAccessibilityAttribute(window, attribute: kAXPositionAttribute as String),
              let sizeValue = context.getAccessibilityAttribute(window, attribute: kAXSizeAttribute as String) else {
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
        size.width  = max(size.width,  200)
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
        if let frame = getWindowFrame(window, context: context) {
            let windowCenter = CGPoint(x: frame.midX, y: frame.midY)
            for screen in NSScreen.screens {
                if screen.frame.contains(windowCenter) { return screen }
            }
            var bestScreen = NSScreen.main
            var maxOverlap: CGFloat = 0
            for screen in NSScreen.screens {
                let overlap = screen.frame.intersection(frame).width * screen.frame.intersection(frame).height
                if overlap > maxOverlap { maxOverlap = overlap; bestScreen = screen }
            }
            return bestScreen
        }
        return NSScreen.main
    }
    
    // MARK: - Positioning Helpers
    
    private func positionWindow(_ window: AXUIElement, relativeTo screen: NSScreen, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, context: PluginContext) {
        let frame = screen.visibleFrame
        let newFrame = CGRect(
            x: frame.minX + x * frame.width,
            y: NSStatusBar.system.thickness + y * frame.height,
            width: width  * frame.width,
            height: height * frame.height
        )
        setWindowFrame(window, frame: newFrame, context: context)
    }
    
    private func positionWindowWithTarget(target: WindowTargeting.WindowTarget?, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, logMessage: String, context: PluginContext) {
        let windows = getTargetWindows(target, context: context)
        guard !windows.isEmpty else { return }
        for (window, _) in windows {
            guard let screen = getScreenForWindow(window, context: context) else { continue }
            positionWindow(window, relativeTo: screen, x: x, y: y, width: width, height: height, context: context)
        }
        context.logger.log("\(logMessage) (\(windows.count) window\(windows.count == 1 ? "" : "s"))", file: #file, function: #function, line: #line)
    }
    
    // MARK: - Sizing and Centering
    
    private func centerWindow(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        let windows = getTargetWindows(target, context: context)
        for (window, _) in windows {
            guard let currentFrame = getWindowFrame(window, context: context),
                  let screen = getScreenForWindow(window, context: context) else { continue }
            let sf = screen.visibleFrame
            let newFrame = CGRect(
                x: sf.midX - currentFrame.width  / 2,
                y: sf.midY - currentFrame.height / 2,
                width:  currentFrame.width,
                height: currentFrame.height
            )
            setWindowFrame(window, frame: newFrame, context: context)
        }
        context.logger.log("Centered \(windows.count) window(s)", file: #file, function: #function, line: #line)
    }
    
    private func resizeToPercent(_ percent: CGFloat, target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        let windows = getTargetWindows(target, context: context)
        for (window, _) in windows {
            guard let screen = getScreenForWindow(window, context: context) else { continue }
            let sf    = screen.visibleFrame
            let scale = percent / 100.0
            let w     = sf.width  * scale
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
            let nw = currentFrame.width  * factor
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
                width:  min(currentFrame.width,  dstF.width),
                height: min(currentFrame.height, dstF.height)
            )
            var o = newOrigin; var s = newSize
            if let pv = AXValueCreate(.cgPoint, &o) { _ = context.setAccessibilityAttribute(window, attribute: kAXPositionAttribute as String, value: pv) }
            if let sv = AXValueCreate(.cgSize,  &s) { _ = context.setAccessibilityAttribute(window, attribute: kAXSizeAttribute  as String, value: sv) }
        }
        context.logger.log("Moved window(s) to display: \(displayParam)", file: #file, function: #function, line: #line)
    }

    private func resizeWindowByPixels(_ delta: CGFloat, target: WindowTargeting.WindowTarget?, logMessage: String, context: PluginContext) {
        let windows = getTargetWindows(target, context: context)
        for (window, _) in windows {
            guard let currentFrame = getWindowFrame(window, context: context) else { continue }
            let nw = max(100, currentFrame.width  + delta)
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
        savedWindowPositions[key] = WindowPosition(
            x: frame.origin.x, y: frame.origin.y,
            width: frame.size.width, height: frame.size.height,
            appIdentifier: bundleId
        )
        saveSavedPositions()
        context.logger.log("Saved window position [\(key)]", file: #file, function: #function, line: #line)
    }
    
    private func restoreWindowPosition(target: WindowTargeting.WindowTarget? = nil, slot: String?, context: PluginContext) {
        guard let (window, pid) = getTargetWindow(target, context: context) else { return }
        let app = NSRunningApplication(processIdentifier: pid)
        let bundleId = app?.bundleIdentifier ?? "unknown"
        let key = slot.map { "slot:\($0)" } ?? "app:\(bundleId)"
        guard let saved = savedWindowPositions[key] else {
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
        savedWindowPositions.removeValue(forKey: key)
        saveSavedPositions()
        context.logger.log("Deleted saved position [\(key)]", file: #file, function: #function, line: #line)
    }
    
    // MARK: - Window Layouts
    
    func getAvailableLayouts() -> [String] {
        return Array(savedLayouts.keys).sorted()
    }

    func getAvailablePositionSlots() -> [String] {
        return Array(savedWindowPositions.keys)
            .filter { $0.hasPrefix("slot:") }
            .map { String($0.dropFirst("slot:".count)) }
            .sorted()
    }
    
    func hasLayout(named name: String) -> Bool {
        return savedLayouts[name] != nil
    }
    
    func deleteLayout(named name: String) {
        savedLayouts.removeValue(forKey: name)
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
        savedLayouts[name] = WindowLayout(name: name, windows: windowInfos)
        saveLayoutsToDisk()
        context.logger.log("Saved layout '\(name)' with \(windowInfos.count) windows", file: #file, function: #function, line: #line)
    }
    
    private func restoreWindowLayout(name: String, reopenApps: Bool = true, context: PluginContext) {
        guard let layout = savedLayouts[name] else {
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
        if let w = params.width           { newSize.width  = CGFloat(w) }
        else if let wp = params.widthPercent  { newSize.width  = sf.width  * CGFloat(wp) / 100 }
        if let h = params.height          { newSize.height = CGFloat(h) }
        else if let hp = params.heightPercent { newSize.height = sf.height * CGFloat(hp) / 100 }
        if params.maintainAspectRatio {
            let ratio = currentFrame.width / currentFrame.height
            if params.width != nil || params.widthPercent != nil { newSize.height = newSize.width / ratio }
            else { newSize.width = newSize.height * ratio }
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
            if let xp = params.xPercent { newPos.x = sf.minX + sf.width  * CGFloat(xp) / 100 }
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
            case .topLeft:      newPos = CGPoint(x: sf.minX,             y: axTop)
            case .topCenter:    newPos = CGPoint(x: sf.midX - w / 2,     y: axTop)
            case .topRight:     newPos = CGPoint(x: sf.maxX - w,          y: axTop)
            case .middleLeft:   newPos = CGPoint(x: sf.minX,             y: axMid - h / 2)
            case .center:       newPos = CGPoint(x: sf.midX - w / 2,     y: axMid - h / 2)
            case .middleRight:  newPos = CGPoint(x: sf.maxX - w,          y: axMid - h / 2)
            case .bottomLeft:   newPos = CGPoint(x: sf.minX,             y: axBottom - h)
            case .bottomCenter: newPos = CGPoint(x: sf.midX - w / 2,     y: axBottom - h)
            case .bottomRight:  newPos = CGPoint(x: sf.maxX - w,          y: axBottom - h)
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
        do {
            let data = try JSONEncoder().encode(savedWindowPositions)
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
            savedWindowPositions = try JSONDecoder().decode([String: WindowPosition].self, from: data)
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
        do {
            let data = try JSONEncoder().encode(savedLayouts)
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
            savedLayouts = try JSONDecoder().decode([String: WindowLayout].self, from: data)
            context.logger.log("Loaded \(savedLayouts.count) window layouts", file: #file, function: #function, line: #line)
        } catch {
            context.logger.log("Error loading window layouts: \(error)", file: #file, function: #function, line: #line)
        }
    }
}
