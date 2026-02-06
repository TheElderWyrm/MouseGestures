import Cocoa
import Foundation
import SwiftUI

// MARK: - Bundle Actions Plugin with Integrated UI

/// Built-in plugin providing bundle action execution with integrated UI components
class BundleActionsPlugin: NSObject, GestureActionPlugin {
    
    // MARK: - Plugin Properties
    
    let identifier = "com.mousegestures.bundle"
    let name = "Bundle Actions"
    override var description: String { "Execute multiple actions sequentially with conditions" }
    let version = "3.0.0" // Version 3.0: SwiftUI Bundle Editor
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
        return nil
    }
    
    func hasAdvancedConfiguration(for action: PluginAction) -> Bool {
        return action.id == "execute_bundle"
    }
    
    func presentAdvancedConfiguration(
        for action: PluginAction,
        currentParameters: [String: AnyCodable],
        parentWindow: NSWindow,
        completion: @escaping ([String: AnyCodable]?) -> Void
    ) {
        guard action.id == "execute_bundle" else {
            completion(nil)
            return
        }
        
        // Decode existing bundled actions from parameters
        var existingActions: [BundledAction] = []
        if let bundleData = currentParameters["bundle_actions"] {
            if let array = bundleData.value as? [[String: Any]] {
                existingActions = array.compactMap { dict in
                    guard let id = dict["actionIdentifier"] as? String else { return nil }
                    let params = (dict["parameters"] as? [String: Any])?.mapValues { AnyCodable($0) } ?? [:]
                    let delay = dict["delayAfter"] as? TimeInterval
                    let condData = dict["conditionData"] as? Data
                    return BundledAction(actionIdentifier: id, parameters: params, delayAfter: delay, conditionData: condData)
                }
            } else if let jsonStr = bundleData.value as? String,
                      let data = jsonStr.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode([BundledAction].self, from: data) {
                existingActions = decoded
            }
        }
        
        // Read bundle-level settings from current parameters
        let stopOnFailure = (currentParameters["stop_on_failure"]?.value as? Bool) ?? false
        let parallelExecution = (currentParameters["parallel_execution"]?.value as? Bool) ?? false
        
        // Present the SwiftUI bundle editor
        let host = BundleEditorWindowHost()
        host.present(
            bundledActions: existingActions,
            stopOnFailure: stopOnFailure,
            parallelExecution: parallelExecution,
            parentWindow: parentWindow,
            completion: { actions, stop, parallel in
                var updatedParams = currentParameters
                let actionDicts: [[String: Any]] = actions.map { ba in
                    var dict: [String: Any] = ["actionIdentifier": ba.actionIdentifier]
                    if !ba.parameters.isEmpty {
                        dict["parameters"] = ba.parameters.mapValues { $0.value }
                    }
                    if let delay = ba.delayAfter {
                        dict["delayAfter"] = delay
                    }
                    if let condData = ba.conditionData {
                        dict["conditionData"] = condData
                    }
                    return dict
                }
                updatedParams["bundle_actions"] = AnyCodable(actionDicts)
                updatedParams["stop_on_failure"] = AnyCodable(stop)
                updatedParams["parallel_execution"] = AnyCodable(parallel)
                completion(updatedParams)
            },
            onCancel: {
                completion(nil)
            }
        )
    }
    
    // MARK: - Private Implementation
    
    private func executeBundle(parameters: ActionParameters, context: PluginContext) throws {
        let stopOnFailure = parameters.bool(for: "stop_on_failure") ?? false
        let parallel = parameters.bool(for: "parallel_execution") ?? false
        
        guard let bundleData = parameters["bundle_actions"] else {
            context.logger.log("No bundle actions provided", file: #file, function: #function, line: #line)
            return
        }
        
        let bundledActions: [BundledAction]
        if let data = bundleData.value as? Data {
            bundledActions = (try? JSONDecoder().decode([BundledAction].self, from: data)) ?? []
        } else if let array = bundleData.value as? [[String: Any]] {
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
        defer { activeExecutions.remove(executionId) }
        
        context.logger.log("Executing bundle with \(bundledActions.count) actions", file: #file, function: #function, line: #line)
        
        if parallel {
            executeActionsInParallel(bundledActions, context: context)
        } else {
            executeActionsSequentially(bundledActions, stopOnFailure: stopOnFailure, context: context)
        }
    }
    
    private func executeActionsSequentially(_ actions: [BundledAction], stopOnFailure: Bool, context: PluginContext) {
        for (index, bundledAction) in actions.enumerated() {
            guard activeExecutions.contains(where: { _ in true }) else {
                context.logger.log("Bundle execution cancelled", file: #file, function: #function, line: #line)
                break
            }
            
            if !bundledAction.shouldExecute() {
                context.logger.log("Skipping action \(bundledAction.actionIdentifier) due to condition", file: #file, function: #function, line: #line)
                continue
            }
            
            context.logger.log("Executing action \(index + 1)/\(actions.count): \(bundledAction.actionIdentifier)", file: #file, function: #function, line: #line)
            
            do {
                if let (_, action) = PluginManager.shared.getAction(identifier: bundledAction.actionIdentifier) {
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
            
            if let delay = bundledAction.delayAfter, delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
        }
    }
    
    private func executeActionsInParallel(_ actions: [BundledAction], context: PluginContext) {
        let group = DispatchGroup()
        
        for bundledAction in actions {
            if !bundledAction.shouldExecute() {
                context.logger.log("Skipping action \(bundledAction.actionIdentifier) due to condition", file: #file, function: #function, line: #line)
                continue
            }
            
            group.enter()
            executionQueue.async {
                defer { group.leave() }
                
                guard self.activeExecutions.contains(where: { _ in true }) else {
                    context.logger.log("Bundle execution cancelled", file: #file, function: #function, line: #line)
                    return
                }
                
                context.logger.log("Executing action (parallel): \(bundledAction.actionIdentifier)", file: #file, function: #function, line: #line)
                
                do {
                    if let (_, action) = PluginManager.shared.getAction(identifier: bundledAction.actionIdentifier) {
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
                
                if let delay = bundledAction.delayAfter, delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }
            }
        }
        
        group.wait()
        context.logger.log("Parallel bundle execution completed", file: #file, function: #function, line: #line)
    }
    
    private func executeConditional(parameters: ActionParameters, context: PluginContext) throws {
        guard let conditionData = parameters["condition"] else {
            context.logger.log("No condition provided", file: #file, function: #function, line: #line)
            return
        }
        
        let conditionGroup: BundleConditionGroup
        if let data = conditionData.value as? Data {
            conditionGroup = (try? JSONDecoder().decode(BundleConditionGroup.self, from: data)) ?? BundleConditionGroup()
        } else {
            conditionGroup = BundleConditionGroup()
        }
        
        let conditionResult = conditionGroup.evaluate()
        context.logger.log("Condition evaluated to: \(conditionResult)", file: #file, function: #function, line: #line)
        
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
