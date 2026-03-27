import Cocoa
import Carbon
import Foundation
import SwiftUI

// MARK: - Plugin-Specific Types

/// Structure to store bundled actions for sequential execution
struct BundledAction: Codable, Equatable {
    var id: UUID = UUID()
    var actionIdentifier: String
    var parameters: [String: AnyCodable]
    var delayAfter: TimeInterval?
    var conditionData: Data?

    init(actionIdentifier: String, parameters: [String: AnyCodable] = [:], delayAfter: TimeInterval? = 0.2, conditionData: Data? = nil) {
        self.actionIdentifier = actionIdentifier
        self.parameters = parameters
        self.delayAfter = delayAfter
        self.conditionData = conditionData
    }

    // Computed property for easier condition access
    var condition: BundleConditionGroup? {
        get {
            guard let data = conditionData else { return nil }
            return try? JSONDecoder().decode(BundleConditionGroup.self, from: data)
        }
        set {
            if let newValue = newValue {
                conditionData = try? JSONEncoder().encode(newValue)
            } else {
                conditionData = nil
            }
        }
    }

    // Check if this action should execute based on its condition
    func shouldExecute() -> Bool {
        guard let condition = condition else { return true } // No condition = always execute
        return condition.evaluate()
    }

    var displayName: String {
        var name: String
        if let (_, action) = PluginManager.shared.getAction(identifier: actionIdentifier) {
            name = action.name
        } else {
            name = actionIdentifier
        }

        // Add condition indicator if present
        if let condition = condition, !condition.conditions.isEmpty {
            name = "[IF] " + name
        }

        return name
    }
}

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
            description: "Execute an action only when a condition is met",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "condition_type",
                    name: "Condition",
                    type: .selection,
                    defaultValue: AnyCodable("app_frontmost"),
                    description: "When to execute the action",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("always"),
                        AnyCodable("app_frontmost"),
                        AnyCodable("app_running"),
                        AnyCodable("window_title_contains"),
                        AnyCodable("profile_active")
                    ]),
                    displayValues: [
                        "always": "Always",
                        "app_frontmost": "App Is Frontmost",
                        "app_running": "App Is Running",
                        "window_title_contains": "Window Title Contains",
                        "profile_active": "Profile Is Active"
                    ]
                ),
                ParameterDefinition(
                    key: "condition_negate",
                    name: "Negate Condition",
                    type: .boolean,
                    defaultValue: AnyCodable(false),
                    description: "Execute when condition is NOT met"
                ),
                ParameterDefinition(
                    key: "condition_app",
                    name: "Application",
                    type: .application,
                    description: "Application to check",
                    visibleWhen: ParameterVisibilityRule(key: "condition_type", anyOf: ["app_frontmost", "app_running"])
                ),
                ParameterDefinition(
                    key: "condition_window_title",
                    name: "Window Title",
                    type: .string,
                    description: "Text the window title must contain",
                    visibleWhen: ParameterVisibilityRule(key: "condition_type", value: "window_title_contains")
                ),
                ParameterDefinition(
                    key: "condition_profile",
                    name: "Profile",
                    type: .profile,
                    description: "Profile that must be active",
                    visibleWhen: ParameterVisibilityRule(key: "condition_type", value: "profile_active")
                ),
                ParameterDefinition(
                    key: "nested_action_id",
                    name: "Action to Run",
                    type: .actionId,
                    description: "The action to execute when condition is met"
                ),
                ParameterDefinition(
                    key: "false_action_id",
                    name: "Action if False",
                    type: .actionId,
                    description: "Action to run when condition is NOT met (optional)"
                ),
                ParameterDefinition(
                    key: "nested_action_params",
                    name: "Action Parameters",
                    type: .json,
                    description: "Parameters for the nested action"
                ),
                ParameterDefinition(
                    key: "false_action_params",
                    name: "False Action Parameters",
                    type: .json,
                    description: "Parameters for the false-branch action"
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
                    type: .actionId,
                    required: true,
                    description: "Action to repeat"
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
            icon: "clock",
            hidden: true
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
            guard parameters.string(for: "nested_action_id") != nil else {
                return .invalid(error: "An action to run is required")
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
        return action.id == "execute_bundle" || action.id == "conditional_action"
    }

    func presentAdvancedConfiguration(
        for action: PluginAction,
        currentParameters: [String: AnyCodable],
        parentWindow: NSWindow,
        completion: @escaping ([String: AnyCodable]?) -> Void
    ) {
        if action.id == "conditional_action" {
            presentConditionalActionEditor(currentParameters: currentParameters, parentWindow: parentWindow, completion: completion)
            return
        }
        guard action.id == "execute_bundle" else {
            completion(nil)
            return
        }
        
        // Decode existing bundled actions from parameters
        let existingActions: [BundledAction] = {
            guard let bundleData = currentParameters["bundle_actions"] else { return [] }
            return Self.decodeBundledActions(from: bundleData)
        }()
        
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
    
    // MARK: - Conditional Action Editor

    private func presentConditionalActionEditor(
        currentParameters: [String: AnyCodable],
        parentWindow: NSWindow,
        completion: @escaping ([String: AnyCodable]?) -> Void
    ) {
        let trueActionId  = currentParameters["nested_action_id"]?.value as? String ?? ""
        let falseActionId = currentParameters["false_action_id"]?.value as? String ?? ""
        let trueParamsJson  = currentParameters["nested_action_params"]?.value as? String ?? ""
        let falseParamsJson = currentParameters["false_action_params"]?.value as? String ?? ""

        func decodeParams(_ json: String) -> [String: AnyCodable] {
            guard !json.isEmpty, let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return dict.mapValues { AnyCodable($0) }
        }

        let editorView = ConditionalActionEditorView(
            trueActionId: trueActionId,
            trueActionParams: decodeParams(trueParamsJson),
            falseActionId: falseActionId,
            falseActionParams: decodeParams(falseParamsJson)
        ) { tId, tParams, fId, fParams in
            var updated = currentParameters
            updated["nested_action_id"] = AnyCodable(tId)
            updated["false_action_id"]  = AnyCodable(fId)
            func encodeParams(_ p: [String: AnyCodable]) -> String {
                guard !p.isEmpty,
                      let data = try? JSONSerialization.data(withJSONObject: p.mapValues { $0.value }),
                      let s = String(data: data, encoding: .utf8) else { return "" }
                return s
            }
            updated["nested_action_params"] = AnyCodable(encodeParams(tParams))
            updated["false_action_params"]  = AnyCodable(encodeParams(fParams))
            completion(updated)
        } onCancel: {
            completion(nil)
        }

        let controller = NSHostingController(rootView: editorView)
        let window = NSWindow(contentViewController: controller)
        window.title = "Configure Conditional Action"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 680))
        window.minSize = NSSize(width: 700, height: 500)
        parentWindow.beginSheet(window) { _ in }
    }

    // MARK: - Private Implementation

    private func executeBundle(parameters: ActionParameters, context: PluginContext) throws {
        let stopOnFailure = parameters.bool(for: "stop_on_failure") ?? false
        let parallel = parameters.bool(for: "parallel_execution") ?? false
        
        guard let bundleData = parameters["bundle_actions"] else {
            context.logger.log("No bundle actions provided", file: #file, function: #function, line: #line)
            return
        }
        
        let bundledActions = Self.decodeBundledActions(from: bundleData)
        guard !bundledActions.isEmpty else {
            context.logger.log("Bundle actions empty or could not be decoded", file: #file, function: #function, line: #line)
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
    
    /// Execute a single bundled sub-action directly through its plugin, bypassing
    /// the full sandbox enter/exit cycle that can interfere when multiple actions
    /// target the same plugin in rapid succession.
    private func executeBundledSubAction(_ bundledAction: BundledAction, context: PluginContext) throws {
        guard let (plugin, action) = PluginManager.shared.getAction(identifier: bundledAction.actionIdentifier) else {
            throw PluginError.actionNotFound(bundledAction.actionIdentifier)
        }
        try plugin.execute(
            action: action,
            with: ActionParameters(values: bundledAction.parameters),
            context: context
        )
    }

    private func executeActionsSequentially(_ actions: [BundledAction], stopOnFailure: Bool, context: PluginContext) {
        context.logger.log("Sequential bundle: \(actions.count) actions to execute", file: #file, function: #function, line: #line)

        for (index, bundledAction) in actions.enumerated() {
            guard activeExecutions.contains(where: { _ in true }) else {
                context.logger.log("Bundle execution cancelled at action \(index + 1)", file: #file, function: #function, line: #line)
                break
            }

            if !bundledAction.shouldExecute() {
                context.logger.log("Skipping action \(index + 1)/\(actions.count) (\(bundledAction.actionIdentifier)) due to condition", file: #file, function: #function, line: #line)
                continue
            }

            context.logger.log("Executing action \(index + 1)/\(actions.count): \(bundledAction.actionIdentifier)", file: #file, function: #function, line: #line)

            do {
                try executeBundledSubAction(bundledAction, context: context)
                context.logger.log("Completed action \(index + 1)/\(actions.count): \(bundledAction.actionIdentifier)", file: #file, function: #function, line: #line)
            } catch {
                context.logger.log("Failed action \(index + 1)/\(actions.count) (\(bundledAction.actionIdentifier)): \(error)", file: #file, function: #function, line: #line)
                if stopOnFailure {
                    context.logger.log("Stopping bundle execution due to failure", file: #file, function: #function, line: #line)
                    break
                }
            }

            if let delay = bundledAction.delayAfter, delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
        }

        context.logger.log("Sequential bundle execution finished", file: #file, function: #function, line: #line)
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
                    try self.executeBundledSubAction(bundledAction, context: context)
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
        let conditionType = parameters.string(for: "condition_type") ?? "always"
        let negate = parameters.bool(for: "condition_negate") ?? false
        let conditionMet: Bool

        switch conditionType {
        case "always":
            conditionMet = true
        case "app_frontmost":
            let bundleId = parameters.string(for: "condition_app") ?? ""
            conditionMet = context.getFrontmostApplication()?.bundleIdentifier == bundleId
        case "app_running":
            let bundleId = parameters.string(for: "condition_app") ?? ""
            conditionMet = context.getRunningApplications().contains { $0.bundleIdentifier == bundleId && !$0.isTerminated }
        case "window_title_contains":
            let titlePart = (parameters.string(for: "condition_window_title") ?? "").lowercased()
            let frontApp = context.getFrontmostApplication()
            let appEl = frontApp.map { AXUIElementCreateApplication($0.processIdentifier) }
            var windowTitle = ""
            if let appEl = appEl {
                var focusedRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
                   let focused = focusedRef {
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(unsafeBitCast(focused, to: AXUIElement.self), kAXTitleAttribute as CFString, &titleRef)
                    windowTitle = (titleRef as? String ?? "").lowercased()
                }
            }
            conditionMet = !titlePart.isEmpty && windowTitle.contains(titlePart)
        case "profile_active":
            let profileName = (parameters.string(for: "condition_profile") ?? "").lowercased()
            let activeProfiles = context.getProfiles().filter { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == context.getActiveProfileId() }
            conditionMet = activeProfiles.contains { ($0["name"] as? String ?? "").lowercased() == profileName }
        default:
            conditionMet = false
        }

        let shouldExecute = negate ? !conditionMet : conditionMet
        context.logger.log("Condition '\(conditionType)' evaluated to: \(conditionMet), negate: \(negate), execute: \(shouldExecute)", file: #file, function: #function, line: #line)

        // Get nested action params
        var nestedParams: [String: AnyCodable] = [:]
        if let paramsJson = parameters.string(for: "nested_action_params"),
           let data = paramsJson.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in dict { nestedParams[k] = AnyCodable(v) }
        }

        if shouldExecute {
            guard let nestedActionId = parameters.string(for: "nested_action_id"), !nestedActionId.isEmpty else {
                context.logger.log("No nested action ID specified", file: #file, function: #function, line: #line)
                return
            }
            try executeBundledSubAction(
                BundledAction(actionIdentifier: nestedActionId, parameters: nestedParams, delayAfter: nil),
                context: context
            )
        } else {
            // Run false branch if specified
            if let falseActionId = parameters.string(for: "false_action_id"), !falseActionId.isEmpty {
                var falseParams: [String: AnyCodable] = [:]
                if let paramsJson = parameters.string(for: "false_action_params"),
                   let data = paramsJson.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for (k, v) in dict { falseParams[k] = AnyCodable(v) }
                }
                try executeBundledSubAction(
                    BundledAction(actionIdentifier: falseActionId, parameters: falseParams, delayAfter: nil),
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
        
        guard PluginManager.shared.getAction(identifier: actionId) != nil else {
            context.logger.log("Action not found: \(actionId)", file: #file, function: #function, line: #line)
            return
        }

        let subAction = BundledAction(actionIdentifier: actionId, parameters: actionParams, delayAfter: nil)

        for i in 1...count {
            guard activeExecutions.contains(where: { _ in true }) else {
                context.logger.log("Repeat execution cancelled", file: #file, function: #function, line: #line)
                break
            }

            context.logger.log("Repeat \(i)/\(count)", file: #file, function: #function, line: #line)

            try executeBundledSubAction(subAction, context: context)

            if i < count && delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
        }
    }
    
    /// Decode a list of BundledActions from an AnyCodable value, handling all persistence formats:
    /// - `[[String: Any]]` — in-memory representation before serialisation
    /// - `[Any]` — AnyCodable-decoded JSON array (produced after app restart)
    /// - `Data` — raw JSON-encoded BundledAction array
    /// - `String` — JSON string fallback
    private static func decodeBundledActions(from bundleData: AnyCodable) -> [BundledAction] {
        // Raw Data (legacy direct JSONDecoder path)
        if let data = bundleData.value as? Data {
            return (try? JSONDecoder().decode([BundledAction].self, from: data)) ?? []
        }

        // Normalise the raw value into [[String: Any]] regardless of whether AnyCodable
        // stored it as [[String: Any]] (in-memory) or [Any] (post-JSON-decode).
        let rawArray: [Any]?
        if let typed = bundleData.value as? [[String: Any]] {
            rawArray = typed
        } else if let untyped = bundleData.value as? [Any] {
            rawArray = untyped
        } else if let jsonStr = bundleData.value as? String,
                  let data = jsonStr.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([BundledAction].self, from: data) {
            return decoded
        } else {
            return []
        }

        return rawArray?.compactMap { element -> BundledAction? in
            guard let dict = element as? [String: Any],
                  let id = dict["actionIdentifier"] as? String else { return nil }
            let params = (dict["parameters"] as? [String: Any])?.mapValues { AnyCodable($0) } ?? [:]
            let delay = parseTimeInterval(dict["delayAfter"])
            let condData = dict["conditionData"] as? Data
            return BundledAction(actionIdentifier: id, parameters: params, delayAfter: delay, conditionData: condData)
        } ?? []
    }

    /// Parse a TimeInterval from Any, handling both Int and Double after AnyCodable round-tripping.
    /// AnyCodable decodes whole JSON numbers (e.g. 1.0) as Int, so a plain `as? TimeInterval` cast
    /// would fail and lose the configured value.
    private static func parseTimeInterval(_ value: Any?) -> TimeInterval? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    private func executeDelay(parameters: ActionParameters, context: PluginContext) {
        let duration = parameters.number(for: "duration") ?? 1.0
        context.logger.log("Delaying for \(duration) seconds", file: #file, function: #function, line: #line)
        Thread.sleep(forTimeInterval: duration)
    }
}
