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
                validation: ValidationRule(minValue: 1),
                visibleWhen: ParameterVisibilityRule(key: "target", value: "by_age"),
                group: "Target"
            )
        ]
    }
    
    // MARK: - Actions
    
    lazy var providedActions: [PluginAction] = [
        
        // MARK: Snap Window (replaces individual half/quarter/third actions)
        PluginAction(
            id: "snap_window",
            name: "Snap Window",
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
        
        // Center
        PluginAction(
            id: "center",
            name: "Center Window",
            description: "Center window on screen",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.center.inset.filled"
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
                    key: "percent",
                    name: "Amount",
                    type: .number,
                    defaultValue: AnyCodable(10),
                    description: "Percentage to adjust by",
                    validation: ValidationRule(minValue: 1, maxValue: 100),
                    suffix: "%"
                )
            ] + windowTargetParameters,
            supportsRepeat: true,
            icon: "arrow.up.backward.and.arrow.down.forward"
        ),
        
        // MARK: Cycle Windows (replaces cycle_windows_forward / cycle_windows_backward)
        PluginAction(
            id: "cycle_windows",
            name: "Cycle Windows",
            description: "Cycle through windows",
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
                )
            ] + windowTargetParameters,
            supportsRepeat: true,
            icon: "arrow.clockwise.circle"
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
                    description: "Named slot for the position (optional, defaults to app bundle ID)"
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
                    description: "Name of the layout"
                ),
                ParameterDefinition(
                    key: "reopen_apps",
                    name: "Reopen Apps",
                    type: .boolean,
                    defaultValue: AnyCodable(true),
                    description: "Launch apps that aren't running (restore only)"
                )
            ],
            icon: "rectangle.3.group"
        ),
        
        // MARK: Tile / Cascade
        PluginAction(
            id: "tile_all",
            name: "Tile All Windows",
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
                        AnyCodable("all_windows")
                    ]),
                    displayValues: ["current_app": "Current App", "all_windows": "All Windows"]
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
                )
            ] + windowTargetParameters,
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
            
        // MARK: Snap Window
        case "snap_window":
            let position = parameters.string(for: "position") ?? "left_half"
            snapWindow(to: position, target: target, context: context)
            
        // Center
        case "center":
            centerWindow(target: target, context: context)
            
        // MARK: Resize
        case "resize_to_percent":
            let percent = parameters.number(for: "percent") ?? 50
            resizeToPercent(percent, target: target, context: context)
            
        case "adjust_size":
            let direction = parameters.string(for: "direction") ?? "grow"
            let percent = parameters.number(for: "percent") ?? 10
            let factor: CGFloat = direction == "grow"
                ? 1.0 + (percent / 100.0)
                : 1.0 - (percent / 100.0)
            let msg = direction == "grow" ? "Grew window by \(Int(percent))%" : "Shrank window by \(Int(percent))%"
            resizeWindowByFactor(factor, target: target, logMessage: msg, context: context)
            
        // MARK: Window Navigation
        case "cycle_windows":
            let forward = (parameters.string(for: "direction") ?? "forward") == "forward"
            cycleWindows(forward: forward, target: target, context: context)
            
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
            let tileTarget: WindowTargeting.WindowTarget?
            if tileScope == "all_windows" {
                var t = WindowTargeting.WindowTarget()
                t.targetType = .allWindows
                tileTarget = t
            } else {
                tileTarget = target
            }
            tileAllWindows(target: tileTarget, context: context)
        case "cascade":
            let cascadeScope = parameters.string(for: "scope") ?? "current_app"
            let cascadeTarget: WindowTargeting.WindowTarget?
            if cascadeScope == "all_windows" {
                var t = WindowTargeting.WindowTarget()
                t.targetType = .allWindows
                cascadeTarget = t
            } else {
                cascadeTarget = target
            }
            cascadeWindows(target: cascadeTarget, context: context)
            
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
            let positionType = WindowPositionParameters.PositionType(
                rawValue: positionTypeStr.replacingOccurrences(of: "_", with: " ").capitalized
            ) ?? .absolute
            
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
            // Keep the window's top-left position — only change size, don't reposition
            let newFrame = CGRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y,
                width: nw, height: nh
            )
            setWindowFrame(window, frame: newFrame, context: context)
        }
        context.logger.log(logMessage, file: #file, function: #function, line: #line)
    }
    
    // MARK: - Window Navigation
    
    private func cycleWindows(forward: Bool, target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        if let target = target {
            switch target.targetType {
            case .byApplication, .allWindowsOfApp:
                let targetWindows = context.getAllVisibleWindows().filter { (_, pid) in
                    if let bundleId = target.applicationBundleId,
                       let app = NSRunningApplication(processIdentifier: pid) {
                        return app.bundleIdentifier == bundleId
                    }
                    return true
                }
                guard !targetWindows.isEmpty else { return }
                var currentIndex: Int?
                for (index, (window, _)) in targetWindows.enumerated() {
                    if let v = context.getAccessibilityAttribute(window, attribute: kAXFocusedAttribute as String),
                       let focused = v as? Bool, focused {
                        currentIndex = index; break
                    }
                }
                let nextIndex: Int
                if let cur = currentIndex {
                    nextIndex = forward ? (cur + 1) % targetWindows.count : (cur > 0 ? cur - 1 : targetWindows.count - 1)
                } else {
                    nextIndex = forward ? 0 : targetWindows.count - 1
                }
                _ = context.performAccessibilityAction(targetWindows[nextIndex].0, action: kAXRaiseAction as String)
                context.logger.log("Cycled to \(forward ? "next" : "previous") window", file: #file, function: #function, line: #line)
            default:
                cycleWindowsStandard(forward: forward, context: context)
            }
        } else {
            cycleWindowsStandard(forward: forward, context: context)
        }
    }
    
    private func cycleWindowsStandard(forward: Bool, context: PluginContext) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyCode: CGKeyCode = 50
        let modifiers: CGEventFlags = forward ? [.maskCommand] : [.maskCommand, .maskShift]
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        keyDown.flags = modifiers; keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        usleep(50000)
        keyUp.post(tap: .cghidEventTap)
    }
    
    private func switchToWindow(target: WindowTargeting.WindowTarget?, context: PluginContext) {
        guard let target = target,
              let (window, _) = getTargetWindow(target, context: context) else { return }
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
    
    private func tileAllWindows(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        let windows = getAppWindows(target: target, context: context)
        guard !windows.isEmpty, let screen = NSScreen.main else { return }
        let sf  = screen.visibleFrame
        let cnt = windows.count
        
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
            let xOffset = isLastRow ? CGFloat(0) : CGFloat(0) // Last row windows fill evenly
            
            let frame = CGRect(
                x: sf.minX + CGFloat(effectiveCol) * winW + xOffset,
                y: sf.minY + sf.height - CGFloat(row + 1) * winH,
                width: winW, height: winH
            )
            setWindowFrame(window, frame: frame, context: context)
        }
        context.logger.log("Tiled \(cnt) windows in \(cols)x\(rows) grid", file: #file, function: #function, line: #line)
    }
    
    private func cascadeWindows(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        // Filter out desktop widget windows (owned by WidgetKit or Notification Center)
        let widgetBundlePrefixes = ["com.apple.notificationcenterui", "com.apple.WidgetKit"]
        let allWindows = getAppWindows(target: target, context: context)
        let windows = allWindows.filter { window in
            // Get the PID for this window and check its bundle ID
            var pid: pid_t = 0
            AXUIElementGetPid(window, &pid)
            if let app = NSRunningApplication(processIdentifier: pid),
               let bundleId = app.bundleIdentifier {
                return !widgetBundlePrefixes.contains(where: { bundleId.hasPrefix($0) })
            }
            return true
        }
        guard !windows.isEmpty, let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let offset: CGFloat = 30
        let winSize = CGSize(width: sf.width * 0.6, height: sf.height * 0.6)
        
        // Wrap cascade position when it would go off screen
        let maxOffset = min(sf.width - winSize.width, sf.height - winSize.height)
        
        for (idx, window) in windows.enumerated() {
            let rawOff = CGFloat(idx) * offset
            let off = rawOff.truncatingRemainder(dividingBy: max(maxOffset, offset))
            let frame = CGRect(
                x: sf.minX + off,
                y: sf.maxY - winSize.height - off,
                width: winSize.width, height: winSize.height
            )
            setWindowFrame(window, frame: frame, context: context)
        }
        context.logger.log("Cascaded \(windows.count) windows", file: #file, function: #function, line: #line)
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
            switch preset {
            case .topLeft:      newPos = CGPoint(x: sf.minX,                             y: sf.maxY - currentFrame.height)
            case .topCenter:    newPos = CGPoint(x: sf.midX - currentFrame.width / 2,    y: sf.maxY - currentFrame.height)
            case .topRight:     newPos = CGPoint(x: sf.maxX - currentFrame.width,         y: sf.maxY - currentFrame.height)
            case .middleLeft:   newPos = CGPoint(x: sf.minX,                             y: sf.midY - currentFrame.height / 2)
            case .center:       newPos = CGPoint(x: sf.midX - currentFrame.width / 2,    y: sf.midY - currentFrame.height / 2)
            case .middleRight:  newPos = CGPoint(x: sf.maxX - currentFrame.width,         y: sf.midY - currentFrame.height / 2)
            case .bottomLeft:   newPos = CGPoint(x: sf.minX,                             y: sf.minY)
            case .bottomCenter: newPos = CGPoint(x: sf.midX - currentFrame.width / 2,    y: sf.minY)
            case .bottomRight:  newPos = CGPoint(x: sf.maxX - currentFrame.width,         y: sf.minY)
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
