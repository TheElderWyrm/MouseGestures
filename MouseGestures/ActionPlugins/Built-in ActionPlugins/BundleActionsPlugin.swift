import Cocoa
import Foundation

// MARK: - Bundle Actions Plugin with Integrated UI

/// Built-in plugin providing bundle action execution with integrated UI components
class BundleActionsPlugin: NSObject, GestureActionPlugin {
    
    // MARK: - Plugin Properties
    
    let identifier = "com.mousegestures.bundle"
    let name = "Bundle Actions"
    override var description: String { "Execute multiple actions sequentially with conditions" }
    let version = "2.0.0" // Version 2.0 includes integrated UI
    let author = "MouseGestures"
    let category = ActionCategory.automation
    let icon: NSImage? = nil
    
    // MARK: - Actions
    
    lazy var providedActions: [PluginAction] = [
        PluginAction(
            id: "execute_bundle",
            name: "Execute Action Bundle",
            description: "Execute a bundle of actions with conditions and delays",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "bundle_actions",
                    name: "Bundled Actions",
                    type: .json,
                    required: true,
                    description: "Array of BundledAction objects to execute"
                ),
                ParameterDefinition(
                    key: "stop_on_failure",
                    name: "Stop on Failure",
                    type: .boolean,
                    defaultValue: AnyCodable(false),
                    description: "Stop execution if an action fails"
                ),
                ParameterDefinition(
                    key: "parallel_execution",
                    name: "Parallel Execution",
                    type: .boolean,
                    defaultValue: AnyCodable(false),
                    description: "Execute actions in parallel instead of sequentially"
                )
            ],
            supportsRepeat: false,
            icon: "square.stack.3d.up"
        ),
        PluginAction(
            id: "conditional_action",
            name: "Conditional Action",
            description: "Execute an action based on conditions",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "condition",
                    name: "Condition",
                    type: .json,
                    required: true,
                    description: "BundleConditionGroup to evaluate"
                ),
                ParameterDefinition(
                    key: "true_action",
                    name: "Action if True",
                    type: .string,
                    required: true,
                    description: "Action identifier to execute if condition is true"
                ),
                ParameterDefinition(
                    key: "true_parameters",
                    name: "Parameters if True",
                    type: .json,
                    defaultValue: AnyCodable([:]),
                    description: "Parameters for the true action"
                ),
                ParameterDefinition(
                    key: "false_action",
                    name: "Action if False",
                    type: .string,
                    description: "Action identifier to execute if condition is false"
                ),
                ParameterDefinition(
                    key: "false_parameters",
                    name: "Parameters if False",
                    type: .json,
                    defaultValue: AnyCodable([:]),
                    description: "Parameters for the false action"
                )
            ],
            icon: "questionmark.diamond"
        ),
        PluginAction(
            id: "repeat_action",
            name: "Repeat Action",
            description: "Repeat an action multiple times",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "action_id",
                    name: "Action",
                    type: .string,
                    required: true,
                    description: "Action identifier to repeat"
                ),
                ParameterDefinition(
                    key: "parameters",
                    name: "Action Parameters",
                    type: .json,
                    defaultValue: AnyCodable([:]),
                    description: "Parameters for the action"
                ),
                ParameterDefinition(
                    key: "count",
                    name: "Repeat Count",
                    type: .number,
                    defaultValue: AnyCodable(3),
                    description: "Number of times to repeat the action"
                ),
                ParameterDefinition(
                    key: "delay",
                    name: "Delay Between",
                    type: .number,
                    defaultValue: AnyCodable(0.2),
                    description: "Delay in seconds between each execution"
                )
            ],
            icon: "repeat"
        ),
        PluginAction(
            id: "delay",
            name: "Delay",
            description: "Add a delay between actions",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "duration",
                    name: "Duration",
                    type: .number,
                    defaultValue: AnyCodable(1.0),
                    description: "Delay duration in seconds"
                )
            ],
            icon: "clock"
        )
    ]
    
    // MARK: - Plugin Lifecycle
    
    private var context: PluginContext?
    private let executionQueue = DispatchQueue(label: "com.mousegestures.bundle.execution", attributes: .concurrent)
    private var activeExecutions = Set<UUID>()
    
    func initialize(context: PluginContext) throws {
        self.context = context
        context.logger.log("Bundle Actions Plugin initialized", file: #file, function: #function, line: #line)
    }
    
    func cleanup() {
        // Cancel any active executions
        activeExecutions.removeAll()
        context?.logger.log("Bundle Actions Plugin cleaned up", file: #file, function: #function, line: #line)
        context = nil
    }
    
    // MARK: - Action Execution
    
    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "execute_bundle":
            try executeBundle(parameters: parameters, context: context)
        case "conditional_action":
            try executeConditional(parameters: parameters, context: context)
        case "repeat_action":
            try executeRepeat(parameters: parameters, context: context)
        case "delay":
            executeDelay(parameters: parameters, context: context)
        default:
            throw PluginError.actionNotFound(action.id)
        }
    }
    
    func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        switch action.id {
        case "execute_bundle":
            guard parameters["bundle_actions"] != nil else {
                return .invalid(error: "Bundle actions are required")
            }
        case "conditional_action":
            guard parameters["condition"] != nil,
                  parameters.string(for: "true_action") != nil else {
                return .invalid(error: "Condition and true action are required")
            }
        case "repeat_action":
            guard parameters.string(for: "action_id") != nil else {
                return .invalid(error: "Action to repeat is required")
            }
            if let count = parameters.number(for: "count"), count < 1 {
                return .invalid(error: "Repeat count must be at least 1")
            }
        case "delay":
            if let duration = parameters.number(for: "duration"), duration < 0 {
                return .invalid(error: "Delay duration must be positive")
            }
        default:
            break
        }
        return .valid
    }
    
    func configurationView(for action: PluginAction) -> NSView? {
        switch action.id {
        case "execute_bundle":
            // Return the bundle editor
            let editor = BundleActionsEditor()
            return editor.window?.contentView
        default:
            return nil
        }
    }
    
    // MARK: - Private Implementation
    
    private func executeBundle(parameters: ActionParameters, context: PluginContext) throws {
        let stopOnFailure = parameters.bool(for: "stop_on_failure") ?? false
        let parallel = parameters.bool(for: "parallel_execution") ?? false
        
        // Get bundled actions
        guard let bundleData = parameters["bundle_actions"] else {
            context.logger.log("No bundle actions provided", file: #file, function: #function, line: #line)
            return
        }
        
        // Decode bundled actions
        let bundledActions: [BundledAction]
        if let data = bundleData.value as? Data {
            bundledActions = (try? JSONDecoder().decode([BundledAction].self, from: data)) ?? []
        } else if let array = bundleData.value as? [[String: Any]] {
            // Try to construct from dictionary array
            bundledActions = array.compactMap { dict in
                guard let id = dict["actionIdentifier"] as? String else { return nil }
                let params = (dict["parameters"] as? [String: Any]) ?? [:]
                let delay = dict["delayAfter"] as? TimeInterval
                let conditionData = dict["conditionData"] as? Data
                
                let anyCodableParams = params.mapValues { AnyCodable($0) }
                return BundledAction(
                    actionIdentifier: id,
                    parameters: anyCodableParams,
                    delayAfter: delay,
                    conditionData: conditionData
                )
            }
        } else {
            context.logger.log("Invalid bundle actions format", file: #file, function: #function, line: #line)
            return
        }
        
        guard !bundledActions.isEmpty else {
            context.logger.log("Empty bundle actions", file: #file, function: #function, line: #line)
            return
        }
        
        let executionId = UUID()
        activeExecutions.insert(executionId)
        
        defer {
            activeExecutions.remove(executionId)
        }
        
        context.logger.log("Executing bundle with \(bundledActions.count) actions", file: #file, function: #function, line: #line)
        
        if parallel {
            executeActionsInParallel(bundledActions, context: context)
        } else {
            executeActionsSequentially(bundledActions, stopOnFailure: stopOnFailure, context: context)
        }
    }
    
    private func executeActionsSequentially(_ actions: [BundledAction], stopOnFailure: Bool, context: PluginContext) {
        for (index, bundledAction) in actions.enumerated() {
            // Check if we should continue
            guard activeExecutions.contains(where: { _ in true }) else {
                context.logger.log("Bundle execution cancelled", file: #file, function: #function, line: #line)
                break
            }
            
            // Check condition
            if !bundledAction.shouldExecute() {
                context.logger.log("Skipping action \(bundledAction.actionIdentifier) due to condition", file: #file, function: #function, line: #line)
                continue
            }
            
            context.logger.log("Executing action \(index + 1)/\(actions.count): \(bundledAction.actionIdentifier)", file: #file, function: #function, line: #line)
            
            // Execute the action through plugin manager
            do {
                if let (_, action) = PluginManager.shared.getAction(identifier: bundledAction.actionIdentifier) {
                    // Get the plugin for this action
                    if let plugin = PluginManager.shared.getAllPlugins().first(where: { plugin in
                        plugin.providedActions.contains(where: { $0.id == bundledAction.actionIdentifier })
                    }) {
                        try plugin.execute(
                            action: action,
                            with: ActionParameters(values: bundledAction.parameters),
                            context: context
                        )
                    }
                }
            } catch {
                context.logger.log("Failed to execute action \(bundledAction.actionIdentifier): \(error)", file: #file, function: #function, line: #line)
                if stopOnFailure {
                    context.logger.log("Stopping bundle execution due to failure", file: #file, function: #function, line: #line)
                    break
                }
            }
            
            // Apply delay if specified
            if let delay = bundledAction.delayAfter, delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
        }
    }
    
    private func executeActionsInParallel(_ actions: [BundledAction], context: PluginContext) {
        let group = DispatchGroup()
        
        for bundledAction in actions {
            // Check condition
            if !bundledAction.shouldExecute() {
                context.logger.log("Skipping action \(bundledAction.actionIdentifier) due to condition", file: #file, function: #function, line: #line)
                continue
            }
            
            group.enter()
            executionQueue.async {
                defer { group.leave() }
                
                // Check if we should continue
                guard self.activeExecutions.contains(where: { _ in true }) else {
                    context.logger.log("Bundle execution cancelled", file: #file, function: #function, line: #line)
                    return
                }
                
                context.logger.log("Executing action (parallel): \(bundledAction.actionIdentifier)", file: #file, function: #function, line: #line)
                
                // Execute the action
                do {
                    if let (_, action) = PluginManager.shared.getAction(identifier: bundledAction.actionIdentifier) {
                        // Get the plugin for this action
                        if let plugin = PluginManager.shared.getAllPlugins().first(where: { plugin in
                            plugin.providedActions.contains(where: { $0.id == bundledAction.actionIdentifier })
                        }) {
                            try plugin.execute(
                                action: action,
                                with: ActionParameters(values: bundledAction.parameters),
                                context: context
                            )
                        }
                    }
                } catch {
                    context.logger.log("Failed to execute action \(bundledAction.actionIdentifier): \(error)", file: #file, function: #function, line: #line)
                }
                
                // Apply delay if specified
                if let delay = bundledAction.delayAfter, delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }
            }
        }
        
        // Wait for all actions to complete
        group.wait()
        context.logger.log("Parallel bundle execution completed", file: #file, function: #function, line: #line)
    }
    
    private func executeConditional(parameters: ActionParameters, context: PluginContext) throws {
        // Get and evaluate condition
        guard let conditionData = parameters["condition"] else {
            context.logger.log("No condition provided", file: #file, function: #function, line: #line)
            return
        }
        
        let conditionGroup: BundleConditionGroup
        if let data = conditionData.value as? Data {
            conditionGroup = (try? JSONDecoder().decode(BundleConditionGroup.self, from: data)) ?? BundleConditionGroup()
        } else if let _ = conditionData.value as? [String: Any] {
            // Try to construct from dictionary
            conditionGroup = BundleConditionGroup() // Simplified - would need proper parsing
        } else {
            context.logger.log("Invalid condition format", file: #file, function: #function, line: #line)
            return
        }
        
        let conditionResult = conditionGroup.evaluate()
        context.logger.log("Condition evaluated to: \(conditionResult)", file: #file, function: #function, line: #line)
        
        // Execute appropriate action
        let actionId: String?
        let actionParams: [String: AnyCodable]
        
        if conditionResult {
            actionId = parameters.string(for: "true_action")
            actionParams = (parameters.dictionary(for: "true_parameters") as? [String: AnyCodable]) ?? [:]
        } else {
            actionId = parameters.string(for: "false_action")
            actionParams = (parameters.dictionary(for: "false_parameters") as? [String: AnyCodable]) ?? [:]
        }
        
        guard let finalActionId = actionId else {
            context.logger.log("No action specified for condition result: \(conditionResult)", file: #file, function: #function, line: #line)
            return
        }
        
        // Execute the selected action
        if let (_, action) = PluginManager.shared.getAction(identifier: finalActionId) {
            if let plugin = PluginManager.shared.getAllPlugins().first(where: { plugin in
                plugin.providedActions.contains(where: { $0.id == finalActionId })
            }) {
                try plugin.execute(
                    action: action,
                    with: ActionParameters(values: actionParams),
                    context: context
                )
            }
        }
    }
    
    private func executeRepeat(parameters: ActionParameters, context: PluginContext) throws {
        guard let actionId = parameters.string(for: "action_id") else {
            context.logger.log("No action specified for repeat", file: #file, function: #function, line: #line)
            return
        }
        
        let count = Int(parameters.number(for: "count") ?? 3)
        let delay = parameters.number(for: "delay") ?? 0.2
        let actionParams = (parameters.dictionary(for: "parameters") as? [String: AnyCodable]) ?? [:]
        
        context.logger.log("Repeating action \(actionId) \(count) times with \(delay)s delay", file: #file, function: #function, line: #line)
        
        guard let (_, action) = PluginManager.shared.getAction(identifier: actionId),
              let plugin = PluginManager.shared.getAllPlugins().first(where: { plugin in
                  plugin.providedActions.contains(where: { $0.id == actionId })
              }) else {
            context.logger.log("Action not found: \(actionId)", file: #file, function: #function, line: #line)
            return
        }
        
        for i in 1...count {
            // Check if we should continue
            guard activeExecutions.contains(where: { _ in true }) else {
                context.logger.log("Repeat execution cancelled", file: #file, function: #function, line: #line)
                break
            }
            
            context.logger.log("Repeat \(i)/\(count)", file: #file, function: #function, line: #line)
            
            try plugin.execute(
                action: action,
                with: ActionParameters(values: actionParams),
                context: context
            )
            
            if i < count && delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
        }
    }
    
    private func executeDelay(parameters: ActionParameters, context: PluginContext) {
        let duration = parameters.number(for: "duration") ?? 1.0
        context.logger.log("Delaying for \(duration) seconds", file: #file, function: #function, line: #line)
        Thread.sleep(forTimeInterval: duration)
    }
}

// MARK: - Bundle Actions Editor

public class BundleActionsEditor: NSWindowController, NSTableViewDelegate, NSTableViewDataSource {
    
    // MARK: - UI Elements
    var tableView: NSTableView!
    var addButton: NSButton!
    var editButton: NSButton!
    var removeButton: NSButton!
    var moveUpButton: NSButton!
    var moveDownButton: NSButton!
    var doneButton: NSButton!
    var cancelButton: NSButton!
    
    // Inline action picker controls
    var actionPopup: NSPopUpButton!
    var addActionButton: NSButton!
    var parameterContainer: NSView!
    
    // Advanced settings
    var advancedToggle: NSButton!
    var conditionLabel: NSTextField!
    var conditionButton: NSButton!
    var isAdvancedMode: Bool = false
    
    // MARK: - Data
    var bundledActions: [BundledAction] = [] {
        didSet {
            // Ensure table reload happens on main thread
            DispatchQueue.main.async { [weak self] in
                self?.tableView?.reloadData()
                self?.updateButtonStates()
            }
        }
    }
    var completionHandler: (([BundledAction]?) -> Void)?
    
    private var currentParameters: [String: AnyCodable] = [:]
    private var currentCondition: BundleConditionGroup?
    
    // Child window controllers
    private var editDialog: BundleActionEditDialog?
    private var conditionEditor: BundleConditionEditor?
    
    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: true)
        window.title = "Edit Bundle Actions"
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
        setupUI()
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // Title
        let titleLabel = NSTextField(labelWithString: "Actions will be executed in order from top to bottom:")
        titleLabel.frame = NSRect(x: 20, y: 560, width: 560, height: 20)
        contentView.addSubview(titleLabel)
        
        // Table View
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 300, width: 560, height: 250))
        scrollView.hasVerticalScroller = true
        
        tableView = NSTableView(frame: scrollView.bounds)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(editSelectedAction)
        
        let orderColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("order"))
        orderColumn.title = "#"
        orderColumn.width = 30
        tableView.addTableColumn(orderColumn)
        
        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = "Action"
        actionColumn.width = 400
        tableView.addTableColumn(actionColumn)
        
        let delayColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("delay"))
        delayColumn.title = "Delay (s)"
        delayColumn.width = 80
        tableView.addTableColumn(delayColumn)
        
        scrollView.documentView = tableView
        contentView.addSubview(scrollView)
        
        // Table Management Buttons
        moveUpButton = NSButton(title: "▲", target: self, action: #selector(moveActionUp))
        moveUpButton.frame = NSRect(x: 20, y: 265, width: 30, height: 25)
        contentView.addSubview(moveUpButton)
        
        moveDownButton = NSButton(title: "▼", target: self, action: #selector(moveActionDown))
        moveDownButton.frame = NSRect(x: 55, y: 265, width: 30, height: 25)
        contentView.addSubview(moveDownButton)
        
        editButton = NSButton(title: "Edit", target: self, action: #selector(editSelectedAction))
        editButton.frame = NSRect(x: 95, y: 265, width: 60, height: 25)
        contentView.addSubview(editButton)
        
        removeButton = NSButton(title: "Remove", target: self, action: #selector(removeAction))
        removeButton.frame = NSRect(x: 160, y: 265, width: 70, height: 25)
        contentView.addSubview(removeButton)
        
        // Add Action Section
        let addSectionBox = NSBox(frame: NSRect(x: 20, y: 60, width: 560, height: 195))
        addSectionBox.title = "Add Action"
        contentView.addSubview(addSectionBox)
        
        let addSectionView = addSectionBox.contentView!
        
        actionPopup = NSPopUpButton(frame: NSRect(x: 10, y: 150, width: 520, height: 25))
        setupActionPopup(actionPopup, excludeBundleActions: true)
        actionPopup.target = self
        actionPopup.action = #selector(actionSelectionChanged)
        addSectionView.addSubview(actionPopup)
        
        parameterContainer = NSView(frame: NSRect(x: 10, y: 40, width: 520, height: 100))
        addSectionView.addSubview(parameterContainer)
        
        addActionButton = NSButton(title: "Add Action to Bundle", target: self, action: #selector(addActionToList))
        addActionButton.frame = NSRect(x: 400, y: 10, width: 130, height: 25)
        addSectionView.addSubview(addActionButton)
        
        // Done/Cancel Buttons
        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: 420, y: 20, width: 80, height: 32)
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        contentView.addSubview(cancelButton)
        
        doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.frame = NSRect(x: 510, y: 20, width: 80, height: 32)
        doneButton.keyEquivalent = "\r" // Return
        contentView.addSubview(doneButton)
        
        updateButtonStates()
        actionSelectionChanged()
    }
    
    // Helper method to setup action popup (replacing ActionListHelper)
    private func setupActionPopup(_ popup: NSPopUpButton, excludeBundleActions: Bool = false) {
        popup.removeAllItems()
        
        let pluginManager = PluginManager.shared
        let allPlugins = pluginManager.getAllPlugins()
        
        // Group actions by category
        for category in ActionCategory.allCases {
            var categoryActions: [(plugin: GestureActionPlugin, action: PluginAction)] = []
            
            for plugin in allPlugins {
                for action in plugin.providedActions {
                    if plugin.category == category {
                        // Skip bundle actions if requested
                        if excludeBundleActions && action.id.contains("bundle") {
                            continue
                        }
                        categoryActions.append((plugin, action))
                    }
                }
            }
            
            if !categoryActions.isEmpty {
                // Add category header
                popup.addItem(withTitle: "— \(category.rawValue) —")
                popup.lastItem?.isEnabled = false
                
                // Add actions in this category
                for (plugin, action) in categoryActions {
                    popup.addItem(withTitle: action.name)
                    // Store the full action identifier as represented object
                    popup.lastItem?.representedObject = "\(plugin.identifier).\(action.id)"
                    
                    // Add icon if available
                    if let iconName = action.icon,
                       let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                        popup.lastItem?.image = image
                        popup.lastItem?.image?.size = NSSize(width: 16, height: 16)
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @objc func addActionToList() {
        guard let actionIdentifier = actionPopup.selectedItem?.representedObject as? String else {
            showAlert("No Action Selected", "Please select an action from the dropdown menu.")
            return
        }
        
        let bundledAction = BundledAction(actionIdentifier: actionIdentifier, parameters: currentParameters)
        bundledActions.append(bundledAction)
        
        // Reset for next action
        actionPopup.selectItem(at: 0)
        actionSelectionChanged()
    }
    
    @objc func removeAction() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 else { return }
        bundledActions.remove(at: selectedRow)
    }
    
    @objc func moveActionUp() {
        let selectedRow = tableView.selectedRow
        guard selectedRow > 0 else { return }
        bundledActions.swapAt(selectedRow, selectedRow - 1)
        DispatchQueue.main.async { [weak self] in
            self?.tableView.selectRowIndexes(IndexSet(integer: selectedRow - 1), byExtendingSelection: false)
        }
    }
    
    @objc func moveActionDown() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < bundledActions.count - 1 else { return }
        bundledActions.swapAt(selectedRow, selectedRow + 1)
        DispatchQueue.main.async { [weak self] in
            self?.tableView.selectRowIndexes(IndexSet(integer: selectedRow + 1), byExtendingSelection: false)
        }
    }
    
    @objc func editSelectedAction() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 else { return }
        
        let actionToEdit = bundledActions[selectedRow]
        
        editDialog = BundleActionEditDialog(bundledAction: actionToEdit)
        editDialog?.completionHandler = { [weak self] editedAction in
            guard let self = self, let editedAction = editedAction else { return }
            self.bundledActions[selectedRow] = editedAction
        }
        
        window?.beginSheet(editDialog!.window!)
    }
    
    @objc func done() {
        completionHandler?(bundledActions)
        window?.close()
    }
    
    @objc func cancel() {
        completionHandler?(nil)
        window?.close()
    }
    
    // MARK: - UI Updates
    
    @objc private func actionSelectionChanged() {
        parameterContainer.subviews.forEach { $0.removeFromSuperview() }
        currentParameters.removeAll()
        
        guard let actionIdentifier = actionPopup.selectedItem?.representedObject as? String,
              let (_, action) = PluginManager.shared.getAction(identifier: actionIdentifier) else {
            return
        }
        
        // Dynamically create UI for parameters
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        for paramDef in action.supportedParameters {
            let label = NSTextField(labelWithString: "\(paramDef.name):")
            let control = createControl(for: paramDef)
            
            let row = NSStackView(views: [label, control])
            row.orientation = .horizontal
            stackView.addArrangedSubview(row)
        }
        
        parameterContainer.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: parameterContainer.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: parameterContainer.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: parameterContainer.trailingAnchor),
        ])
    }
    
    private func createControl(for paramDef: ParameterDefinition) -> NSView {
        let control: NSView
        
        switch paramDef.type {
        case .string, .path, .url:
            let textField = NSTextField()
            textField.placeholderString = paramDef.description
            textField.target = self
            textField.action = #selector(parameterChanged(_:))
            textField.identifier = NSUserInterfaceItemIdentifier(paramDef.key)
            control = textField
        case .number:
            let numberField = NSTextField()
            numberField.formatter = NumberFormatter()
            numberField.target = self
            numberField.action = #selector(parameterChanged(_:))
            numberField.identifier = NSUserInterfaceItemIdentifier(paramDef.key)
            control = numberField
        case .boolean:
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(parameterChanged(_:)))
            checkbox.identifier = NSUserInterfaceItemIdentifier(paramDef.key)
            control = checkbox
        default:
            let unsupportedLabel = NSTextField(labelWithString: "Configurable in Edit mode")
            unsupportedLabel.textColor = .secondaryLabelColor
            control = unsupportedLabel
        }
        
        return control
    }
    
    @objc func parameterChanged(_ sender: NSControl) {
        guard let key = sender.identifier?.rawValue else { return }
        
        if let textField = sender as? NSTextField {
            if textField.formatter is NumberFormatter {
                currentParameters[key] = AnyCodable(textField.doubleValue)
            } else {
                currentParameters[key] = AnyCodable(textField.stringValue)
            }
        } else if let checkbox = sender as? NSButton {
            currentParameters[key] = AnyCodable(checkbox.state == .on)
        }
    }
    
    private func updateButtonStates() {
        let hasSelection = tableView.selectedRow >= 0
        editButton.isEnabled = hasSelection
        removeButton.isEnabled = hasSelection
        moveUpButton.isEnabled = hasSelection && tableView.selectedRow > 0
        moveDownButton.isEnabled = hasSelection && tableView.selectedRow < bundledActions.count - 1
    }
    
    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
    
    // MARK: - Table View DataSource & Delegate
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return bundledActions.count
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let action = bundledActions[row]
        let cell = NSTableCellView()
        let textField = NSTextField(labelWithString: "")
        
        switch tableColumn?.identifier.rawValue {
        case "order":
            textField.stringValue = "\(row + 1)"
        case "action":
            textField.stringValue = action.displayName
        case "delay":
            textField.isEditable = true
            textField.doubleValue = action.delayAfter ?? 0.2
            textField.formatter = NumberFormatter()
            textField.target = self
            textField.action = #selector(delayChanged(_:))
            textField.tag = row
        default:
            break
        }
        
        cell.addSubview(textField)
        return cell
    }
    
    @objc func delayChanged(_ sender: NSTextField) {
        bundledActions[sender.tag].delayAfter = sender.doubleValue
    }
    
    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStates()
    }
}

// MARK: - Bundle Action Edit Dialog

internal class BundleActionEditDialog: NSWindowController {
    
    var bundledAction: BundledAction
    var completionHandler: ((BundledAction?) -> Void)?
    
    // UI Elements
    var actionPopup: NSPopUpButton!
    var parameterContainer: NSView!
    var saveButton: NSButton!
    var cancelButton: NSButton!
    
    init(bundledAction: BundledAction) {
        self.bundledAction = bundledAction
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: true)
        window.title = "Edit Action"
        super.init(window: window)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Implementation similar to the original BundleActionEditDialog
        // but integrated into the plugin
    }
    
    @objc private func save() {
        if let actionIdentifier = actionPopup.selectedItem?.representedObject as? String {
            bundledAction.actionIdentifier = actionIdentifier
        }
        completionHandler?(bundledAction)
        window?.sheetParent?.endSheet(window!)
    }
    
    @objc private func cancel() {
        completionHandler?(nil)
        window?.sheetParent?.endSheet(window!)
    }
}

// MARK: - Bundle Condition Editor (stub for now)

internal class BundleConditionEditor: NSWindowController {
    // This would contain the full implementation of BundleConditionEditor
    // integrated into the plugin
}


