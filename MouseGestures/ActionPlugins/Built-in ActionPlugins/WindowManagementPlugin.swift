import Cocoa
import Carbon

// MARK: - Internal UI Components for Window Management

// Window Layout Editor - integrated into plugin
internal class WindowLayoutEditor: NSWindowController {
    
    var layoutMode: LayoutMode = .save
    var selectedLayoutName: String?
    var reopenApps: Bool = true
    var completionHandler: ((String?, Bool?) -> Void)?
    var plugin: WindowManagementPlugin?
    
    enum LayoutMode {
        case save
        case restore
    }
    
    // UI Elements
    private var layoutPopup: NSPopUpButton!
    private var nameField: NSTextField!
    private var reopenAppsCheckbox: NSButton!
    private var saveButton: NSButton!
    private var cancelButton: NSButton!
    private var deleteButton: NSButton!
    private var instructionLabel: NSTextField!
    
    convenience init(mode: LayoutMode, plugin: WindowManagementPlugin) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        self.init(window: window)
        self.layoutMode = mode
        self.plugin = plugin
        
        window.title = mode == .save ? "Save Window Layout" : "Restore Window Layout"
        window.isReleasedWhenClosed = false
        
        setupUI()
        loadLayouts()
        updateButtonStates()
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // Instruction label
        instructionLabel = NSTextField(labelWithString: "")
        instructionLabel.frame = NSRect(x: 20, y: 150, width: 410, height: 30)
        instructionLabel.alignment = .left
        instructionLabel.maximumNumberOfLines = 2
        instructionLabel.cell?.wraps = true
        contentView.addSubview(instructionLabel)
        
        if layoutMode == .save {
            instructionLabel.stringValue = "Save the current arrangement of all windows. Enter a name for this layout:"
            
            // Name field for save mode
            let nameLabel = NSTextField(labelWithString: "Layout Name:")
            nameLabel.frame = NSRect(x: 20, y: 115, width: 90, height: 20)
            contentView.addSubview(nameLabel)
            
            nameField = NSTextField(frame: NSRect(x: 115, y: 110, width: 315, height: 25))
            nameField.placeholderString = "Enter layout name"
            nameField.delegate = self
            contentView.addSubview(nameField)
            
            // Dropdown to select existing layout to overwrite
            let overwriteLabel = NSTextField(labelWithString: "Or overwrite:")
            overwriteLabel.frame = NSRect(x: 20, y: 80, width: 90, height: 20)
            contentView.addSubview(overwriteLabel)
            
            layoutPopup = NSPopUpButton(frame: NSRect(x: 115, y: 75, width: 315, height: 25))
            layoutPopup.target = self
            layoutPopup.action = #selector(layoutSelected(_:))
            contentView.addSubview(layoutPopup)
            
        } else {
            instructionLabel.stringValue = "Select a saved window layout to restore:"
            
            // Dropdown for restore mode
            let selectLabel = NSTextField(labelWithString: "Layout:")
            selectLabel.frame = NSRect(x: 20, y: 115, width: 90, height: 20)
            contentView.addSubview(selectLabel)
            
            layoutPopup = NSPopUpButton(frame: NSRect(x: 115, y: 110, width: 260, height: 25))
            layoutPopup.target = self
            layoutPopup.action = #selector(layoutSelected(_:))
            contentView.addSubview(layoutPopup)
            
            // Delete button
            deleteButton = NSButton(frame: NSRect(x: 380, y: 110, width: 50, height: 25))
            deleteButton.bezelStyle = .rounded
            deleteButton.title = "Delete"
            deleteButton.target = self
            deleteButton.action = #selector(deleteLayout(_:))
            deleteButton.isEnabled = false
            contentView.addSubview(deleteButton)
            
            // Checkbox for reopening apps
            reopenAppsCheckbox = NSButton(checkboxWithTitle: "Reopen apps if not running", target: self, action: #selector(reopenAppsChanged(_:)))
            reopenAppsCheckbox.frame = NSRect(x: 115, y: 75, width: 250, height: 20)
            reopenAppsCheckbox.state = .on
            contentView.addSubview(reopenAppsCheckbox)
        }
        
        // Info label showing layout count
        let infoLabel = NSTextField(labelWithString: "")
        infoLabel.frame = NSRect(x: 20, y: 45, width: 410, height: 20)
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.identifier = NSUserInterfaceItemIdentifier("infoLabel")
        contentView.addSubview(infoLabel)
        
        // Buttons
        cancelButton = NSButton(frame: NSRect(x: 250, y: 10, width: 80, height: 30))
        cancelButton.bezelStyle = .rounded
        cancelButton.title = "Cancel"
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.keyEquivalent = "\u{1b}" // Escape key
        contentView.addSubview(cancelButton)
        
        saveButton = NSButton(frame: NSRect(x: 340, y: 10, width: 90, height: 30))
        saveButton.bezelStyle = .rounded
        saveButton.title = layoutMode == .save ? "Save" : "Restore"
        saveButton.target = self
        saveButton.action = #selector(save(_:))
        saveButton.keyEquivalent = "\r" // Return key
        saveButton.isEnabled = false
        contentView.addSubview(saveButton)
        
        updateInfoLabel()
    }
    
    private func loadLayouts() {
        layoutPopup.removeAllItems()
        
        if layoutMode == .save {
            layoutPopup.addItem(withTitle: "Select existing layout to overwrite...")
        } else {
            layoutPopup.addItem(withTitle: "Select a layout...")
        }
        
        let layouts = plugin?.getAvailableLayouts() ?? []
        if !layouts.isEmpty {
            layoutPopup.menu?.addItem(NSMenuItem.separator())
            for layout in layouts {
                layoutPopup.addItem(withTitle: layout)
            }
        }
        
        updateInfoLabel()
        updateButtonStates()
    }
    
    private func updateInfoLabel() {
        if let label = window?.contentView?.subviews.first(where: { $0 is NSTextField && ($0 as! NSTextField).identifier?.rawValue == "infoLabel" }) as? NSTextField {
            let count = plugin?.getAvailableLayouts().count ?? 0
            label.stringValue = "\(count) saved layout\(count == 1 ? "" : "s") available"
        }
    }
    
    private func updateButtonStates() {
        if layoutMode == .save {
            let hasName = !(nameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasSelection = layoutPopup.indexOfSelectedItem > 0
            saveButton.isEnabled = hasName || hasSelection
        } else {
            let hasSelection = layoutPopup.indexOfSelectedItem > 0
            saveButton.isEnabled = hasSelection
            deleteButton?.isEnabled = hasSelection
        }
    }
    
    @objc private func layoutSelected(_ sender: NSPopUpButton) {
        if sender.indexOfSelectedItem > 0 {
            selectedLayoutName = sender.titleOfSelectedItem
            
            if layoutMode == .save {
                nameField?.stringValue = selectedLayoutName ?? ""
            }
        } else {
            selectedLayoutName = nil
        }
        
        updateButtonStates()
    }
    
    @objc private func reopenAppsChanged(_ sender: NSButton) {
        reopenApps = sender.state == .on
    }
    
    @objc private func deleteLayout(_ sender: Any) {
        guard let layoutName = selectedLayoutName else { return }
        
        let alert = NSAlert()
        alert.messageText = "Delete Layout"
        alert.informativeText = "Are you sure you want to delete the layout '\(layoutName)'?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            plugin?.deleteLayout(named: layoutName)
            loadLayouts()
            selectedLayoutName = nil
            updateButtonStates()
        }
    }
    
    @objc private func save(_ sender: Any) {
        completionHandler?(selectedLayoutName ?? nameField?.stringValue, reopenApps)
        window?.close()
    }
    
    @objc private func cancel(_ sender: Any) {
        completionHandler?(nil, nil)
        window?.close()
    }
    
    func controlTextDidChange(_ obj: Notification) {
        updateButtonStates()
    }
}

extension WindowLayoutEditor: NSTextFieldDelegate {}

// MARK: - Window Management Plugin

/// Built-in plugin for window management actions - now with all management logic integrated
class WindowManagementPlugin: NSObject, GestureActionPlugin {
    
    // MARK: - Plugin Properties
    
    let identifier = "com.mousegestures.window"
    let name = "Window Management"
    override var description: String { "Window positioning and sizing actions" }
    let version = "2.0.0"
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
    
    // MARK: - Actions
    
    lazy var providedActions: [PluginAction] = [
        // Halves
        PluginAction(
            id: "left_half",
            name: "Move to Left Half",
            description: "Move window to left half of screen",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.lefthalf.filled"
        ),
        PluginAction(
            id: "right_half",
            name: "Move to Right Half",
            description: "Move window to right half of screen",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.righthalf.filled"
        ),
        PluginAction(
            id: "top_half",
            name: "Move to Top Half",
            description: "Move window to top half of screen",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.tophalf.filled"
        ),
        PluginAction(
            id: "bottom_half",
            name: "Move to Bottom Half",
            description: "Move window to bottom half of screen",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.bottomhalf.filled"
        ),
        
        // Quarters
        PluginAction(
            id: "top_left",
            name: "Move to Top Left",
            description: "Move window to top left quarter",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.topleft.filled"
        ),
        PluginAction(
            id: "top_right",
            name: "Move to Top Right",
            description: "Move window to top right quarter",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.topright.filled"
        ),
        PluginAction(
            id: "bottom_left",
            name: "Move to Bottom Left",
            description: "Move window to bottom left quarter",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.bottomleft.filled"
        ),
        PluginAction(
            id: "bottom_right",
            name: "Move to Bottom Right",
            description: "Move window to bottom right quarter",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.bottomright.filled"
        ),
        
        // Thirds
        PluginAction(
            id: "left_third",
            name: "Move to Left Third",
            description: "Move window to left third of screen",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.split.3x1"
        ),
        PluginAction(
            id: "center_third",
            name: "Move to Center Third",
            description: "Move window to center third of screen",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.split.3x1"
        ),
        PluginAction(
            id: "right_third",
            name: "Move to Right Third",
            description: "Move window to right third of screen",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.split.3x1"
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
        
        // Sizing
        PluginAction(
            id: "resize_25",
            name: "Resize to 25%",
            description: "Resize window to 25% of screen",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "arrow.down.right.and.arrow.up.left"
        ),
        PluginAction(
            id: "resize_50",
            name: "Resize to 50%",
            description: "Resize window to 50% of screen",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "arrow.down.right.and.arrow.up.left"
        ),
        PluginAction(
            id: "resize_75",
            name: "Resize to 75%",
            description: "Resize window to 75% of screen",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "arrow.down.right.and.arrow.up.left"
        ),
        PluginAction(
            id: "grow",
            name: "Grow Window",
            description: "Increase window size by 10%",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            supportsRepeat: true,
            icon: "plus.rectangle"
        ),
        PluginAction(
            id: "shrink",
            name: "Shrink Window",
            description: "Decrease window size by 10%",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            supportsRepeat: true,
            icon: "minus.rectangle"
        ),
        
        // Multi-monitor
        PluginAction(
            id: "next_display",
            name: "Move to Next Display",
            description: "Move window to next display",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "display.2"
        ),
        PluginAction(
            id: "previous_display",
            name: "Move to Previous Display",
            description: "Move window to previous display",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "display.2"
        ),
        
        // Window Navigation
        PluginAction(
            id: "cycle_windows_forward",
            name: "Cycle Windows Forward",
            description: "Cycle through windows forward",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "arrow.right.circle"
        ),
        PluginAction(
            id: "cycle_windows_backward",
            name: "Cycle Windows Backward",
            description: "Cycle through windows backward",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "arrow.left.circle"
        ),
        PluginAction(
            id: "switch_to_window",
            name: "Switch to Window",
            description: "Switch to a specific window",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.portrait.and.arrow.right"
        ),
        
        // Layouts
        PluginAction(
            id: "tile_all",
            name: "Tile All Windows",
            description: "Tile all windows on screen",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.split.2x2"
        ),
        PluginAction(
            id: "cascade",
            name: "Cascade Windows",
            description: "Cascade all windows",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "rectangle.stack"
        ),
        PluginAction(
            id: "save_position",
            name: "Save Window Position",
            description: "Save current window position",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "square.and.arrow.down"
        ),
        PluginAction(
            id: "restore_position",
            name: "Restore Window Position",
            description: "Restore saved window position",
            requiresParameters: true,
            supportedParameters: windowTargetParameters,
            icon: "square.and.arrow.up"
        ),
        PluginAction(
            id: "save_layout",
            name: "Save Window Layout",
            description: "Save all window positions",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "layout_name",
                    name: "Layout Name",
                    type: .string,
                    required: true,
                    description: "Name for the layout"
                )
            ],
            icon: "rectangle.3.group"
        ),
        PluginAction(
            id: "restore_layout",
            name: "Restore Window Layout",
            description: "Restore saved window layout",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "layout_name",
                    name: "Layout Name",
                    type: .string,
                    required: true,
                    description: "Name of the layout to restore"
                ),
                ParameterDefinition(
                    key: "reopen_apps",
                    name: "Reopen Apps",
                    type: .boolean,
                    defaultValue: AnyCodable(true),
                    description: "Launch apps that aren't running"
                )
            ],
            icon: "rectangle.3.group"
        ),
        PluginAction(
            id: "delete_layout",
            name: "Delete Window Layout",
            description: "Delete a saved window layout",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "layout_name",
                    name: "Layout Name",
                    type: .string,
                    required: true,
                    description: "Name of the layout to delete"
                )
            ],
            icon: "trash"
        ),
        
        // Custom positioning
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
                    validation: ValidationRule(minValue: 0)
                ),
                ParameterDefinition(
                    key: "height",
                    name: "Height",
                    type: .number,
                    required: false,
                    description: "Window height in pixels",
                    validation: ValidationRule(minValue: 0)
                ),
                ParameterDefinition(
                    key: "width_percent",
                    name: "Width Percentage",
                    type: .number,
                    required: false,
                    description: "Width as percentage of screen",
                    validation: ValidationRule(minValue: 0, maxValue: 100)
                ),
                ParameterDefinition(
                    key: "height_percent",
                    name: "Height Percentage",
                    type: .number,
                    required: false,
                    description: "Height as percentage of screen",
                    validation: ValidationRule(minValue: 0, maxValue: 100)
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
                    ])
                ),
                ParameterDefinition(
                    key: "x",
                    name: "X Position",
                    type: .number,
                    required: false,
                    description: "X coordinate (pixels or percentage)"
                ),
                ParameterDefinition(
                    key: "y",
                    name: "Y Position",
                    type: .number,
                    required: false,
                    description: "Y coordinate (pixels or percentage)"
                ),
                ParameterDefinition(
                    key: "preset",
                    name: "Preset Position",
                    type: .selection,
                    required: false,
                    description: "Preset position when using preset type",
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
                    ])
                )
            ],
            icon: "arrow.up.and.down.and.arrow.left.and.right"
        )
    ]
    
    // Common window target parameters
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
                ])
            ),
            ParameterDefinition(
                key: "app_bundle_id",
                name: "Application",
                type: .application,
                description: "Application when targeting specific window"
            ),
            ParameterDefinition(
                key: "window_title",
                name: "Window Title",
                type: .string,
                description: "Title of the window to target"
            ),
            ParameterDefinition(
                key: "window_age",
                name: "Window Age",
                type: .number,
                defaultValue: AnyCodable(1),
                description: "Age of window (1 = frontmost, 2 = second, etc.)",
                validation: ValidationRule(minValue: 1)
            )
        ]
    }
    
    // MARK: - Plugin Lifecycle
    
    private var context: PluginContext?
    
    func initialize(context: PluginContext) throws {
        self.context = context
        loadSavedPositions(context: context)
        loadLayoutsFromDisk(context: context)
        context.logger.log("Window Management Plugin initialized (self-contained)", file: #file, function: #function, line: #line)
    }
    
    func cleanup() {
        context?.logger.log("Window Management Plugin cleaned up", file: #file, function: #function, line: #line)
        context = nil
    }
    
    // MARK: - Action Execution
    
    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        let target = parseWindowTarget(from: parameters)
        
        switch action.id {
        // Halves
        case "left_half":
            moveToLeftHalf(target: target, context: context)
        case "right_half":
            moveToRightHalf(target: target, context: context)
        case "top_half":
            moveToTopHalf(target: target, context: context)
        case "bottom_half":
            moveToBottomHalf(target: target, context: context)
            
        // Quarters
        case "top_left":
            moveToTopLeft(target: target, context: context)
        case "top_right":
            moveToTopRight(target: target, context: context)
        case "bottom_left":
            moveToBottomLeft(target: target, context: context)
        case "bottom_right":
            moveToBottomRight(target: target, context: context)
            
        // Thirds
        case "left_third":
            moveToLeftThird(target: target, context: context)
        case "center_third":
            moveToCenterThird(target: target, context: context)
        case "right_third":
            moveToRightThird(target: target, context: context)
            
        // Center
        case "center":
            centerWindow(target: target, context: context)
            
        // Sizing
        case "resize_25":
            resizeToPercent(25, target: target, context: context)
        case "resize_50":
            resizeToPercent(50, target: target, context: context)
        case "resize_75":
            resizeToPercent(75, target: target, context: context)
        case "grow":
            growWindow(target: target, context: context)
        case "shrink":
            shrinkWindow(target: target, context: context)
            
        // Multi-monitor
        case "next_display":
            moveToNextDisplay(target: target, context: context)
        case "previous_display":
            moveToPreviousDisplay(target: target, context: context)
            
        // Window Navigation
        case "cycle_windows_forward":
            cycleWindows(forward: true, target: target, context: context)
        case "cycle_windows_backward":
            cycleWindows(forward: false, target: target, context: context)
        case "switch_to_window":
            switchToWindow(target: target, context: context)
            
        // Layouts
        case "tile_all":
            tileAllWindows(target: target, context: context)
        case "cascade":
            cascadeWindows(target: target, context: context)
        case "save_position":
            saveCurrentWindowPosition(target: target, context: context)
        case "restore_position":
            restoreWindowPosition(target: target, context: context)
        case "save_layout":
            if let name = parameters.string(for: "layout_name") {
                saveWindowLayout(name: name, context: context)
            }
        case "restore_layout":
            if let name = parameters.string(for: "layout_name") {
                let reopenApps = parameters.bool(for: "reopen_apps") ?? true
                restoreWindowLayout(name: name, reopenApps: reopenApps, context: context)
            }
        case "delete_layout":
            if let name = parameters.string(for: "layout_name") {
                deleteLayout(named: name)
            }
            
        // Custom positioning
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
            let positionType = WindowPositionParameters.PositionType(rawValue: positionTypeStr.replacingOccurrences(of: "_", with: " ").capitalized) ?? .absolute
            
            var preset: WindowPositionParameters.PresetPosition? = nil
            if let presetStr = parameters.string(for: "preset") {
                // Convert camelCase to proper case with spaces
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
                xPercent: (positionType == .screenPercentage) ? parameters.number(for: "x").map { Int($0) } : nil,
                yPercent: (positionType == .screenPercentage) ? parameters.number(for: "y").map { Int($0) } : nil,
                preset: preset
            )
            setWindowPosition(params: params, target: target, context: context)
            
        default:
            throw PluginError.actionNotFound(action.id)
        }
    }
    
    func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        switch action.id {
        case "save_layout", "restore_layout", "delete_layout":
            if parameters.string(for: "layout_name") == nil {
                return ValidationResult.invalid(error: "Layout name is required")
            }
            
        case "set_size":
            // At least one size parameter must be provided
            let hasWidth = parameters.number(for: "width") != nil
            let hasHeight = parameters.number(for: "height") != nil
            let hasWidthPercent = parameters.number(for: "width_percent") != nil
            let hasHeightPercent = parameters.number(for: "height_percent") != nil
            
            if !hasWidth && !hasHeight && !hasWidthPercent && !hasHeightPercent {
                return ValidationResult.invalid(error: "At least one size parameter is required")
            }
            
        case "set_position":
            let positionType = parameters.string(for: "position_type") ?? "absolute"
            
            switch positionType {
            case "preset":
                if parameters.string(for: "preset") == nil {
                    return ValidationResult.invalid(error: "Preset position is required when using preset type")
                }
            case "absolute", "relative", "screen_percentage":
                if parameters.number(for: "x") == nil && parameters.number(for: "y") == nil {
                    return ValidationResult.invalid(error: "At least one coordinate (X or Y) is required")
                }
            default:
                break
            }
            
        default:
            // For actions that can target specific apps, validate that the app is provided
            if let targetType = parameters.string(for: "target") {
                switch targetType {
                case "by_application", "all_in_app":
                    if parameters.string(for: "app_bundle_id") == nil {
                        return ValidationResult.invalid(error: "An application must be specified for this target type")
                    }
                case "by_title":
                    if parameters.string(for: "window_title") == nil {
                        return ValidationResult.invalid(error: "Window title is required for this target type")
                    }
                case "by_title_contains":
                    if parameters.string(for: "window_title") == nil {
                        return ValidationResult.invalid(error: "Window title pattern is required for this target type")
                    }
                case "by_age":
                    if parameters.number(for: "window_age") == nil {
                        return ValidationResult.invalid(error: "Window age is required for this target type")
                    }
                default:
                    break
                }
            }
        }
        return .valid
    }
    
    func configurationView(for action: PluginAction) -> NSView? {
        // Return custom configuration views for complex actions
        return nil
    }
    
    // MARK: - Core Window Management Functions
    
    private func getTargetWindow(_ target: WindowTargeting.WindowTarget?, context: PluginContext) -> (AXUIElement, pid_t)? {
        let actualTarget = target ?? WindowTargeting.WindowTarget(targetType: .frontmost)
        
        // Convert WindowTarget to params for context
        var params: [String: Any] = [:]
        params["targetType"] = actualTarget.targetType.rawValue
        if let bundleId = actualTarget.applicationBundleId {
            params["bundleId"] = bundleId
        }
        if let title = actualTarget.windowTitle {
            params["windowTitle"] = title
        }
        if let age = actualTarget.windowAge {
            params["windowAge"] = age
        }
        
        return context.getTargetWindow(params)
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
        
        // Ensure minimum window size
        size.width = max(size.width, 200)
        size.height = max(size.height, 150)
        
        if let positionValue = AXValueCreate(.cgPoint, &position),
           let sizeValue = AXValueCreate(.cgSize, &size) {
            let posResult = context.setAccessibilityAttribute(window, attribute: kAXPositionAttribute as String, value: positionValue)
            let sizeResult = context.setAccessibilityAttribute(window, attribute: kAXSizeAttribute as String, value: sizeValue)
            
            if posResult && sizeResult {
                context.logger.log("Window frame set successfully", file: #file, function: #function, line: #line)
            } else {
                context.logger.log("Failed to set window frame", file: #file, function: #function, line: #line)
            }
        }
    }
    
    private func getScreenForWindow(_ window: AXUIElement, context: PluginContext) -> NSScreen? {
        if let frame = getWindowFrame(window, context: context) {
            let windowCenter = CGPoint(x: frame.midX, y: frame.midY)
            
            for screen in NSScreen.screens {
                if screen.frame.contains(windowCenter) {
                    return screen
                }
            }
            
            var bestScreen = NSScreen.main
            var maxOverlap: CGFloat = 0
            
            for screen in NSScreen.screens {
                let intersection = screen.frame.intersection(frame)
                let overlap = intersection.width * intersection.height
                if overlap > maxOverlap {
                    maxOverlap = overlap
                    bestScreen = screen
                }
            }
            
            return bestScreen
        }
        
        return NSScreen.main
    }
    
    // MARK: - Positioning Helper
    
    private func positionWindow(_ window: AXUIElement, relativeTo screen: NSScreen, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, context: PluginContext) {
        let frame = screen.visibleFrame
        
        let actualX = frame.minX + (x * frame.width)
        let actualY = NSStatusBar.system.thickness + (y * frame.height)
        let actualWidth = width * frame.width
        let actualHeight = height * frame.height
        
        let newFrame = CGRect(
            x: actualX,
            y: actualY,
            width: actualWidth,
            height: actualHeight
        )
        
        setWindowFrame(window, frame: newFrame, context: context)
    }
    
    private func positionWindowWithTarget(target: WindowTargeting.WindowTarget? = nil, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, logMessage: String, context: PluginContext) {
        guard let (window, _) = getTargetWindow(target, context: context),
              let screen = getScreenForWindow(window, context: context) else { return }
        
        positionWindow(window, relativeTo: screen, x: x, y: y, width: width, height: height, context: context)
        context.logger.log(logMessage, file: #file, function: #function, line: #line)
    }
    
    // MARK: - Window Positioning Actions
    
    private func moveToLeftHalf(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        positionWindowWithTarget(target: target, x: 0, y: 0, width: 0.5, height: 1,
                                logMessage: "Moved window to left half", context: context)
    }
    
    private func moveToRightHalf(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        positionWindowWithTarget(target: target, x: 0.5, y: 0, width: 0.5, height: 1, logMessage: "Moved window to right half", context: context)
    }
    
    private func moveToTopHalf(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        positionWindowWithTarget(target: target, x: 0, y: 0, width: 1, height: 0.5, logMessage: "Moved window to top half", context: context)
    }
    
    private func moveToBottomHalf(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        positionWindowWithTarget(target: target, x: 0, y: 0.5, width: 1, height: 0.5, logMessage: "Moved window to bottom half", context: context)
    }
    
    private func moveToTopLeft(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        positionWindowWithTarget(target: target, x: 0, y: 0, width: 0.5, height: 0.5, logMessage: "Moved window to top left quarter", context: context)
    }
    
    private func moveToTopRight(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        positionWindowWithTarget(target: target, x: 0.5, y: 0, width: 0.5, height: 0.5, logMessage: "Moved window to top right quarter", context: context)
    }
    
    private func moveToBottomLeft(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        positionWindowWithTarget(target: target, x: 0, y: 0.5, width: 0.5, height: 0.5, logMessage: "Moved window to bottom left quarter", context: context)
    }
    
    private func moveToBottomRight(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        positionWindowWithTarget(target: target, x: 0.5, y: 0.5, width: 0.5, height: 0.5, logMessage: "Moved window to bottom right quarter", context: context)
    }
    
    private func moveToLeftThird(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        positionWindowWithTarget(target: target, x: 0, y: 0, width: 1.0/3.0, height: 1, logMessage: "Moved window to left third", context: context)
    }
    
    private func moveToCenterThird(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        positionWindowWithTarget(target: target, x: 1.0/3.0, y: 0, width: 1.0/3.0, height: 1, logMessage: "Moved window to center third", context: context)
    }
    
    private func moveToRightThird(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        positionWindowWithTarget(target: target, x: 2.0/3.0, y: 0, width: 1.0/3.0, height: 1, logMessage: "Moved window to right third", context: context)
    }
    
    // MARK: - Sizing and Centering
    
    private func centerWindow(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        guard let (window, _) = getTargetWindow(target, context: context),
              let currentFrame = getWindowFrame(window, context: context),
              let screen = getScreenForWindow(window, context: context) else { return }
        
        let screenFrame = screen.visibleFrame
        let newFrame = CGRect(
            x: screenFrame.midX - currentFrame.width / 2,
            y: screenFrame.midY - currentFrame.height / 2,
            width: currentFrame.width,
            height: currentFrame.height
        )
        
        setWindowFrame(window, frame: newFrame, context: context)
        context.logger.log("Centered window", file: #file, function: #function, line: #line)
    }
    
    private func resizeToPercent(_ percent: CGFloat, target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        guard let (window, _) = getTargetWindow(target, context: context),
              let screen = getScreenForWindow(window, context: context) else { return }
        
        let screenFrame = screen.visibleFrame
        let scale = percent / 100.0
        let newWidth = screenFrame.width * scale
        let newHeight = screenFrame.height * scale
        
        let newFrame = CGRect(
            x: screenFrame.midX - newWidth / 2,
            y: screenFrame.midY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
        
        setWindowFrame(window, frame: newFrame, context: context)
        context.logger.log("Resized window to \(percent)%", file: #file, function: #function, line: #line)
    }
    
    private func resizeWindowByFactor(_ factor: CGFloat, target: WindowTargeting.WindowTarget?, logMessage: String, context: PluginContext) {
        guard let (window, _) = getTargetWindow(target, context: context),
              let currentFrame = getWindowFrame(window, context: context) else { return }
        
        let newWidth = currentFrame.width * factor
        let newHeight = currentFrame.height * factor
        
        let newFrame = CGRect(
            x: currentFrame.midX - newWidth / 2,
            y: currentFrame.midY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
        
        setWindowFrame(window, frame: newFrame, context: context)
        context.logger.log(logMessage, file: #file, function: #function, line: #line)
    }
    
    private func growWindow(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        resizeWindowByFactor(1.1, target: target, logMessage: "Grew window by 10%", context: context)
    }
    
    private func shrinkWindow(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        resizeWindowByFactor(0.9, target: target, logMessage: "Shrank window by 10%", context: context)
    }
    
    // MARK: - Multi-Monitor Support
    
    private func moveToDisplay(target: WindowTargeting.WindowTarget?, direction: Int, context: PluginContext) {
        guard let (window, _) = getTargetWindow(target, context: context),
              let currentScreen = getScreenForWindow(window, context: context),
              let currentFrame = getWindowFrame(window, context: context) else { return }
        
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            context.logger.log("Only one display available", file: #file, function: #function, line: #line)
            return
        }
        
        guard let currentIndex = screens.firstIndex(of: currentScreen) else { return }
        
        let targetIndex = direction > 0 ?
            (currentIndex + 1) % screens.count :
            (currentIndex > 0 ? currentIndex - 1 : screens.count - 1)
        let targetScreen = screens[targetIndex]
        
        let currentScreenFrame = currentScreen.visibleFrame
        let targetScreenFrame = targetScreen.visibleFrame
        
        let relativeX = (currentFrame.minX - currentScreenFrame.minX) / currentScreenFrame.width
        let relativeY = (currentFrame.minY - currentScreenFrame.minY) / currentScreenFrame.height
        let relativeWidth = currentFrame.width / currentScreenFrame.width
        let relativeHeight = currentFrame.height / currentScreenFrame.height
        
        let newFrame = CGRect(
            x: targetScreenFrame.minX + (relativeX * targetScreenFrame.width),
            y: targetScreenFrame.minY + (relativeY * targetScreenFrame.height),
            width: relativeWidth * targetScreenFrame.width,
            height: relativeHeight * targetScreenFrame.height
        )
        
        setWindowFrame(window, frame: newFrame, context: context)
        context.logger.log("Moved window to \(direction > 0 ? "next" : "previous") display", file: #file, function: #function, line: #line)
    }
    
    private func moveToNextDisplay(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        moveToDisplay(target: target, direction: 1, context: context)
    }
    
    private func moveToPreviousDisplay(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        moveToDisplay(target: target, direction: -1, context: context)
    }
    
    // MARK: - Window Navigation
    
    private func cycleWindows(forward: Bool, target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        if let target = target {
            switch target.targetType {
            case .byApplication, .allWindowsOfApp:
                let targetWindows = context.getAllVisibleWindows().filter { (window, pid) in
                    // Filter based on target criteria
                    if let bundleId = target.applicationBundleId {
                        if let app = NSRunningApplication(processIdentifier: pid) {
                            return app.bundleIdentifier == bundleId
                        }
                    }
                    return true
                }
                guard !targetWindows.isEmpty else {
                    context.logger.log("No windows found for target application", file: #file, function: #function, line: #line)
                    return
                }
                
                var currentWindowIndex: Int?
                for (index, (window, _)) in targetWindows.enumerated() {
                    if let focusedValue = context.getAccessibilityAttribute(window, attribute: kAXFocusedAttribute as String),
                       let focused = focusedValue as? Bool, focused {
                        currentWindowIndex = index
                        break
                    }
                }
                
                let nextIndex: Int
                if let current = currentWindowIndex {
                    if forward {
                        nextIndex = (current + 1) % targetWindows.count
                    } else {
                        nextIndex = current > 0 ? current - 1 : targetWindows.count - 1
                    }
                } else {
                    nextIndex = forward ? 0 : targetWindows.count - 1
                }
                
                let (nextWindow, _) = targetWindows[nextIndex]
                _ = context.performAccessibilityAction(nextWindow, action: kAXRaiseAction as String)
                context.logger.log("Cycled to \(forward ? "next" : "previous") window in target app", file: #file, function: #function, line: #line)
                
            default:
                cycleWindowsStandard(forward: forward, context: context)
            }
        } else {
            cycleWindowsStandard(forward: forward, context: context)
        }
    }
    
    private func cycleWindowsStandard(forward: Bool, context: PluginContext) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        
        let keyCode: CGKeyCode = 50 // ` key
        let modifiers: CGEventFlags = forward ? [.maskCommand] : [.maskCommand, .maskShift]
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        
        keyDown.post(tap: .cghidEventTap)
        usleep(50000) // 50ms delay
        keyUp.post(tap: .cghidEventTap)
        
        context.logger.log("Sent standard window cycle command", file: #file, function: #function, line: #line)
    }
    
    private func switchToWindow(target: WindowTargeting.WindowTarget?, context: PluginContext) {
        guard let target = target,
              let (window, _) = getTargetWindow(target, context: context) else {
            context.logger.log("No target window to switch to", file: #file, function: #function, line: #line)
            return
        }
        
        let result = context.performAccessibilityAction(window, action: kAXRaiseAction as String)
        if result {
            context.logger.log("Switched to target window", file: #file, function: #function, line: #line)
        } else {
            context.logger.log("Failed to switch to window", file: #file, function: #function, line: #line)
        }
    }
    
    // MARK: - Advanced Window Management
    
    private func getAppWindows(target: WindowTargeting.WindowTarget?, context: PluginContext) -> [AXUIElement] {
        var windows: [AXUIElement] = []
        
        if let target = target, target.targetType == .allWindowsOfApp {
            let targetWindows = context.getAllVisibleWindows().filter { (window, pid) in
                if let bundleId = target.applicationBundleId {
                    if let app = NSRunningApplication(processIdentifier: pid) {
                        return app.bundleIdentifier == bundleId
                    }
                }
                return false
            }
            windows = targetWindows.map { $0.0 }
        } else {
            guard let frontApp = context.getFrontmostApplication() else { return [] }
            
            windows = context.getWindowsForApplication(frontApp.processIdentifier)
        }
        
        return windows
    }
    
    private func tileAllWindows(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        let windows = getAppWindows(target: target, context: context)
        guard !windows.isEmpty, let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowCount = windows.count
        
        let cols = Int(ceil(sqrt(Double(windowCount))))
        let rows = Int(ceil(Double(windowCount) / Double(cols)))
        
        let windowWidth = screenFrame.width / CGFloat(cols)
        let windowHeight = screenFrame.height / CGFloat(rows)
        
        for (index, window) in windows.enumerated() {
            let col = index % cols
            let row = index / cols
            
            let frame = CGRect(
                x: screenFrame.minX + CGFloat(col) * windowWidth,
                y: screenFrame.minY + screenFrame.height - CGFloat(row + 1) * windowHeight,
                width: windowWidth,
                height: windowHeight
            )
            
            setWindowFrame(window, frame: frame, context: context)
        }
        
        context.logger.log("Tiled \(windowCount) windows", file: #file, function: #function, line: #line)
    }
    
    private func cascadeWindows(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        let windows = getAppWindows(target: target, context: context)
        guard !windows.isEmpty, let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let cascadeOffset: CGFloat = 30
        let windowSize = CGSize(
            width: screenFrame.width * 0.6,
            height: screenFrame.height * 0.6
        )
        
        for (index, window) in windows.enumerated() {
            let offset = CGFloat(index) * cascadeOffset
            
            let frame = CGRect(
                x: screenFrame.minX + offset,
                y: screenFrame.maxY - windowSize.height - offset,
                width: windowSize.width,
                height: windowSize.height
            )
            
            setWindowFrame(window, frame: frame, context: context)
        }
        
        context.logger.log("Cascaded \(windows.count) windows", file: #file, function: #function, line: #line)
    }
    
    // MARK: - Window Position Saving/Restoring
    
    private func saveCurrentWindowPosition(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        guard let (window, pid) = getTargetWindow(target, context: context),
              let frame = getWindowFrame(window, context: context) else { return }
        
        let app = NSRunningApplication(processIdentifier: pid)
        guard let bundleId = app?.bundleIdentifier else { return }
        
        let position = WindowPosition(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: frame.size.height,
            appIdentifier: bundleId
        )
        
        savedWindowPositions[bundleId] = position
        saveSavedPositions()
        
        context.logger.log("Saved window position for \(app?.localizedName ?? bundleId)", file: #file, function: #function, line: #line)
    }
    
    private func restoreWindowPosition(target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        guard let (window, pid) = getTargetWindow(target, context: context) else { return }
        
        let app = NSRunningApplication(processIdentifier: pid)
        guard let bundleId = app?.bundleIdentifier,
              let savedPosition = savedWindowPositions[bundleId] else {
            context.logger.log("No saved position for target window", file: #file, function: #function, line: #line)
            return
        }
        
        let frame = CGRect(
            x: savedPosition.x,
            y: savedPosition.y,
            width: savedPosition.width,
            height: savedPosition.height
        )
        
        setWindowFrame(window, frame: frame, context: context)
        context.logger.log("Restored window position for \(app?.localizedName ?? bundleId)", file: #file, function: #function, line: #line)
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
        if let ctx = self.context {
            ctx.logger.log("Deleted window layout: \(name)", file: #file, function: #function, line: #line)
        }
    }
    
    private func saveWindowLayout(name: String, context: PluginContext) {
        var windowInfos: [WindowLayout.WindowInfo] = []
        
        let windows = context.getAllVisibleWindows()
        
        for winInfo in windows {
            guard let frame = getWindowFrame(winInfo.window, context: context) else { continue }
            
            let app = NSRunningApplication(processIdentifier: winInfo.pid)
            guard let bundleId = app?.bundleIdentifier else { continue }
            let appName = app?.localizedName ?? "Unknown"
            
            var windowTitle: String?
            if let titleValue = context.getAccessibilityAttribute(winInfo.window, attribute: kAXTitleAttribute as String) {
                windowTitle = titleValue as? String
            }
            
            var isMinimized = false
            if let minimizedValue = context.getAccessibilityAttribute(winInfo.window, attribute: kAXMinimizedAttribute as String) {
                isMinimized = (minimizedValue as? Bool) ?? false
            }
            
            let windowLayoutInfo = WindowLayout.WindowInfo(
                appBundleIdentifier: bundleId,
                appName: appName,
                windowTitle: windowTitle,
                position: frame.origin,
                size: frame.size,
                isMinimized: isMinimized,
                spaceNumber: nil
            )
            
            windowInfos.append(windowLayoutInfo)
        }
        
        let layout = WindowLayout(name: name, windows: windowInfos)
        savedLayouts[name] = layout
        saveLayoutsToDisk()
        
        context.logger.log("Saved window layout '\(name)' with \(windowInfos.count) windows", file: #file, function: #function, line: #line)
    }
    
    private func restoreWindowLayout(name: String, reopenApps: Bool = true, context: PluginContext) {
        guard let layout = savedLayouts[name] else {
            context.logger.log("No saved layout found with name: \(name)", file: #file, function: #function, line: #line)
            return
        }
        
        context.logger.log("Restoring window layout '\(name)' with \(layout.windows.count) windows", file: #file, function: #function, line: #line)
        
        let windowsByApp = Dictionary(grouping: layout.windows) { $0.appBundleIdentifier }
        
        for (bundleId, windowInfos) in windowsByApp {
            var app: NSRunningApplication?
            
            let runningApps = context.getRunningApplications()
            app = runningApps.first(where: { $0.bundleIdentifier == bundleId })
            
            if app == nil && reopenApps {
                context.logger.log("App not running, launching: \(bundleId)", file: #file, function: #function, line: #line)
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    
                    let semaphore = DispatchSemaphore(value: 0)
                    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { (launchedApp, error) in
                        if let error = error {
                            context.logger.log("Error launching app \(bundleId): \(error)", file: #file, function: #function, line: #line)
                        } else {
                            app = launchedApp
                            context.logger.log("Successfully launched app: \(bundleId)", file: #file, function: #function, line: #line)
                        }
                        semaphore.signal()
                    }
                    
                    _ = semaphore.wait(timeout: .now() + 3.0)
                    Thread.sleep(forTimeInterval: 0.5)
                } else {
                    context.logger.log("Could not find app to launch: \(bundleId)", file: #file, function: #function, line: #line)
                    continue
                }
            }
            
            guard let runningApp = app else {
                context.logger.log("App still not available: \(bundleId)", file: #file, function: #function, line: #line)
                continue
            }
            
            let appWindows = context.getWindowsForApplication(runningApp.processIdentifier)
            guard !appWindows.isEmpty else {
                continue
            }
            
            for (index, windowInfo) in windowInfos.enumerated() {
                guard index < appWindows.count else { break }
                let window = appWindows[index]
                
                let frame = CGRect(
                    origin: windowInfo.position,
                    size: windowInfo.size
                )
                setWindowFrame(window, frame: frame, context: context)
                
                if windowInfo.isMinimized {
                    let minimized = true as CFBoolean
                    _ = context.setAccessibilityAttribute(window, attribute: kAXMinimizedAttribute as String, value: minimized)
                }
            }
        }
        
        context.logger.log("Window layout restoration completed", file: #file, function: #function, line: #line)
    }
    
    // MARK: - Custom Size and Position
    
    private func setWindowSize(params: WindowSizeParameters, target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        guard let (window, _) = getTargetWindow(target, context: context) else { return }
        
        let screen = getScreenForWindow(window, context: context) ?? NSScreen.main
        guard let screen = screen,
              let currentFrame = getWindowFrame(window, context: context) else { return }
        
        let screenFrame = screen.visibleFrame
        var newSize = currentFrame.size
        
        if let width = params.width {
            newSize.width = CGFloat(width)
        } else if let widthPercent = params.widthPercent {
            newSize.width = screenFrame.width * CGFloat(widthPercent) / 100.0
        }
        
        if let height = params.height {
            newSize.height = CGFloat(height)
        } else if let heightPercent = params.heightPercent {
            newSize.height = screenFrame.height * CGFloat(heightPercent) / 100.0
        }
        
        if params.maintainAspectRatio {
            let currentRatio = currentFrame.width / currentFrame.height
            if params.width != nil || params.widthPercent != nil {
                newSize.height = newSize.width / currentRatio
            } else if params.height != nil || params.heightPercent != nil {
                newSize.width = newSize.height * currentRatio
            }
        }
        
        let newFrame = CGRect(
            origin: currentFrame.origin,
            size: newSize
        )
        setWindowFrame(window, frame: newFrame, context: context)
        
        context.logger.log("Set window size: \(params.displayString)", file: #file, function: #function, line: #line)
    }
    
    private func setWindowPosition(params: WindowPositionParameters, target: WindowTargeting.WindowTarget? = nil, context: PluginContext) {
        guard let (window, _) = getTargetWindow(target, context: context) else { return }
        
        let screen = getScreenForWindow(window, context: context) ?? NSScreen.main
        guard let screen = screen,
              let currentFrame = getWindowFrame(window, context: context) else { return }
        
        let screenFrame = screen.visibleFrame
        var newPosition = currentFrame.origin
        
        switch params.positionType {
        case .absolute:
            if let x = params.x {
                newPosition.x = CGFloat(x)
            }
            if let y = params.y {
                newPosition.y = CGFloat(y)
            }
            
        case .relative:
            if let x = params.x {
                newPosition.x += CGFloat(x)
            }
            if let y = params.y {
                newPosition.y += CGFloat(y)
            }
            
        case .screenPercentage:
            if let xPercent = params.xPercent {
                newPosition.x = screenFrame.minX + (screenFrame.width * CGFloat(xPercent) / 100.0)
            }
            if let yPercent = params.yPercent {
                newPosition.y = screenFrame.minY + (screenFrame.height * CGFloat(yPercent) / 100.0)
            }
            
        case .preset:
            guard let preset = params.preset else { break }
            
            switch preset {
            case .topLeft:
                newPosition = CGPoint(x: screenFrame.minX, y: screenFrame.maxY - currentFrame.height)
            case .topCenter:
                newPosition = CGPoint(x: screenFrame.midX - currentFrame.width/2, y: screenFrame.maxY - currentFrame.height)
            case .topRight:
                newPosition = CGPoint(x: screenFrame.maxX - currentFrame.width, y: screenFrame.maxY - currentFrame.height)
            case .middleLeft:
                newPosition = CGPoint(x: screenFrame.minX, y: screenFrame.midY - currentFrame.height/2)
            case .center:
                newPosition = CGPoint(x: screenFrame.midX - currentFrame.width/2, y: screenFrame.midY - currentFrame.height/2)
            case .middleRight:
                newPosition = CGPoint(x: screenFrame.maxX - currentFrame.width, y: screenFrame.midY - currentFrame.height/2)
            case .bottomLeft:
                newPosition = CGPoint(x: screenFrame.minX, y: screenFrame.minY)
            case .bottomCenter:
                newPosition = CGPoint(x: screenFrame.midX - currentFrame.width/2, y: screenFrame.minY)
            case .bottomRight:
                newPosition = CGPoint(x: screenFrame.maxX - currentFrame.width, y: screenFrame.minY)
            }
        }
        
        let newFrame = CGRect(
            origin: newPosition,
            size: currentFrame.size
        )
        setWindowFrame(window, frame: newFrame, context: context)
        
        context.logger.log("Set window position: \(params.displayString)", file: #file, function: #function, line: #line)
    }
    
    // MARK: - Helper Methods
    
    private func parseWindowTarget(from parameters: ActionParameters) -> WindowTargeting.WindowTarget {
        let targetTypeString = parameters.string(for: "target") ?? "frontmost"
        
        var target = WindowTargeting.WindowTarget()
        
        switch targetTypeString {
        case "frontmost":
            target.targetType = .frontmost
            
        case "by_age":
            target.targetType = .byAge
            target.windowAge = parameters.number(for: "window_age").map { Int($0) }
            
        case "by_application":
            target.targetType = .byApplication
            target.applicationBundleId = parameters.string(for: "app_bundle_id")
            
        case "by_title":
            target.targetType = .byWindowTitle
            target.windowTitle = parameters.string(for: "window_title")
            
        case "by_title_contains":
            target.targetType = .byWindowTitleContains
            target.windowTitleContains = parameters.string(for: "window_title")
            
        case "all_in_app":
            target.targetType = .allWindowsOfApp
            target.applicationBundleId = parameters.string(for: "app_bundle_id")
            
        case "all_visible":
            target.targetType = .allWindows
            
        case "mouse_position":
            target.targetType = .mousePosition
            
        case "largest":
            target.targetType = .largestWindow
            
        case "smallest":
            target.targetType = .smallestWindow
            
        default:
            target.targetType = .frontmost
        }
        
        // Fallback: If a target type requires data but doesn't have it, default to frontmost
        switch target.targetType {
        case .byApplication, .allWindowsOfApp:
            if target.applicationBundleId == nil {
                target.targetType = .frontmost
            }
        case .byWindowTitle:
            if target.windowTitle == nil {
                target.targetType = .frontmost
            }
        case .byWindowTitleContains:
            if target.windowTitleContains == nil {
                target.targetType = .frontmost
            }
        case .byAge:
            if target.windowAge == nil {
                target.windowAge = 1
            }
        default:
            break
        }
        
        return target
    }
    
    // MARK: - Persistence
    
    private func savedPositionsURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MouseGestures")
        try? FileManager.default.createDirectory(at: appFolder,
                                                withIntermediateDirectories: true)
        return appFolder.appendingPathComponent("saved_positions.json")
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
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MouseGestures")
        try? FileManager.default.createDirectory(at: appFolder,
                                                withIntermediateDirectories: true)
        return appFolder.appendingPathComponent("window_layouts.json")
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

