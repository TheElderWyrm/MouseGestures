import Cocoa
import Carbon

// MARK: - Action Execution Context

/// Context information for action execution
struct ActionExecutionContext {
    let source: ActionSource
    let gesture: Gesture?
    let modifiers: NSEvent.ModifierFlags
    let timestamp: Date
    let additionalInfo: [String: Any]
    
    enum ActionSource {
        case gesture(zone: ScreenZone, dragState: DragModifier)
        case keyboard(trigger: KeyboardTrigger)
        case mouseButton(button: MouseButtonTrigger.MouseButton)
        case profileSwitch
        case bundled(parentAction: String)
        case `repeat`
        case longPress
        case external // For external API calls
    }
    
    init(source: ActionSource, 
         gesture: Gesture? = nil,
         modifiers: NSEvent.ModifierFlags = [],
         additionalInfo: [String: Any] = [:]) {
        self.source = source
        self.gesture = gesture
        self.modifiers = modifiers
        self.timestamp = Date()
        self.additionalInfo = additionalInfo
    }
}

// MARK: - Action Execution Result

/// Result of an action execution
struct ActionExecutionResult {
    let success: Bool
    let actionId: String?
    let error: Error?
    let executionTime: TimeInterval
    let metadata: [String: Any]
    
    init(success: Bool, 
         actionId: String? = nil,
         error: Error? = nil,
         executionTime: TimeInterval = 0,
         metadata: [String: Any] = [:]) {
        self.success = success
        self.actionId = actionId
        self.error = error
        self.executionTime = executionTime
        self.metadata = metadata
    }
}

// MARK: - Action Execution Delegate

/// Protocol for objects that want to be notified of action execution events
protocol ActionExecutionDelegate: AnyObject {
    func actionExecutionManager(_ manager: ActionExecutionManager, willExecuteAction actionId: String, context: ActionExecutionContext)
    func actionExecutionManager(_ manager: ActionExecutionManager, didExecuteAction actionId: String, result: ActionExecutionResult, context: ActionExecutionContext)
    func actionExecutionManager(_ manager: ActionExecutionManager, didFailToExecuteAction actionId: String, error: Error, context: ActionExecutionContext)
}

// Optional methods with default implementations
extension ActionExecutionDelegate {
    func actionExecutionManager(_ manager: ActionExecutionManager, willExecuteAction actionId: String, context: ActionExecutionContext) {}
    func actionExecutionManager(_ manager: ActionExecutionManager, didExecuteAction actionId: String, result: ActionExecutionResult, context: ActionExecutionContext) {}
    func actionExecutionManager(_ manager: ActionExecutionManager, didFailToExecuteAction actionId: String, error: Error, context: ActionExecutionContext) {}
}

// MARK: - Action Execution Manager

/// Centralized manager for all action executions in the app
/// Works with the new plugin-based gesture system
class ActionExecutionManager {
    
    // In MouseGestures/ActionExecutionManager.swift

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Singleton
    
    static let shared = ActionExecutionManager()
    
    // MARK: - Properties
    
    private let pluginManager = PluginManager.shared
    private let debouncer = ActionDebounce.shared
    
    // Execution tracking
    private var activeExecutions: Set<UUID> = []
    private var executionHistory: [ActionExecutionRecord] = []
    private let executionQueue = DispatchQueue(label: "com.mousegestures.execution", attributes: .concurrent)
    private let historyQueue = DispatchQueue(label: "com.mousegestures.execution.history")
    
    // Delegates
    private var delegates: [ActionExecutionDelegate] = []
    
    // Configuration
    private var maxHistorySize = 100
    private var enableDebouncing = true
    private var enableHapticFeedback = true
    
    // Statistics
    private var executionStats = ActionExecutionStatistics()
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationObservers()
        loadConfiguration()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configurationChanged),
            name: NSNotification.Name("GestureConfigurationChanged"),
            object: nil
        )
    }
    
    private func loadConfiguration() {
        enableHapticFeedback = Configuration.shared.hapticFeedbackEnabled
        // Load other configuration as needed
    }
    
    @objc private func configurationChanged() {
        loadConfiguration()
    }
    
    // MARK: - Main Execution Methods (Plugin-based)
    
    /// Execute a plugin-based gesture
    func executeGesture(_ gesture: Gesture,
                       fromZone zone: ScreenZone? = nil,
                       withDragState dragState: DragModifier = .none,
                       modifiers: NSEvent.ModifierFlags = []) {
        
        let source: ActionExecutionContext.ActionSource
        if let zone = zone {
            source = .gesture(zone: zone, dragState: dragState)
        } else {
            source = .gesture(zone: gesture.zone, dragState: gesture.dragModifier)
        }
        
        let context = ActionExecutionContext(
            source: source,
            gesture: gesture,
            modifiers: modifiers.isEmpty ? gesture.modifiers : modifiers
        )
        
        executeAction(gesture.actionIdentifier, parameters: ActionParameters(values: gesture.parameters), context: context)
    }
    
    /// Execute a keyboard-triggered gesture
    func executeKeyboardTriggeredGesture(_ gesture: Gesture, trigger: KeyboardTrigger) {
        let context = ActionExecutionContext(
            source: .keyboard(trigger: trigger),
            gesture: gesture,
            modifiers: trigger.modifiers
        )
        
        executeAction(gesture.actionIdentifier, parameters: ActionParameters(values: gesture.parameters), context: context)
    }
    
    /// Execute a mouse button-triggered gesture
    func executeMouseButtonTriggeredGesture(_ gesture: Gesture,
                                           button: MouseButtonTrigger.MouseButton,
                                           modifiers: NSEvent.ModifierFlags) {
        let context = ActionExecutionContext(
            source: .mouseButton(button: button),
            gesture: gesture,
            modifiers: modifiers
        )
        
        executeAction(gesture.actionIdentifier, parameters: ActionParameters(values: gesture.parameters), context: context)
    }
    
    /// Execute a profile switch
    func executeProfileSwitch(_ profile: ConfigurationProfile) {
        let context = ActionExecutionContext(
            source: .profileSwitch,
            additionalInfo: ["profile_id": profile.id.uuidString, "profile_name": profile.name]
        )
        
        // Profile switching is handled directly
        DispatchQueue.main.async {
            ProfileManager.shared.switchToProfile(withId: profile.id)
            self.provideHapticFeedback()
            
            let result = ActionExecutionResult(
                success: true,
                actionId: "profile.switch.\(profile.id.uuidString)",
                executionTime: 0,
                metadata: ["profile_name": profile.name]
            )
            
            self.recordExecution(actionId: "profile.switch", result: result, context: context)
        }
    }
    
    /// Execute a repeated gesture
    func executeRepeatedGesture(_ gesture: Gesture) {
        let context = ActionExecutionContext(
            source: .repeat,
            gesture: gesture,
            modifiers: gesture.modifiers
        )
        
        // Skip debouncing for repeated actions
        executeActionWithoutDebounce(gesture.actionIdentifier, 
                                    parameters: ActionParameters(values: gesture.parameters),
                                    context: context)
    }
    
    /// Execute bundled actions
    func executeBundledActions(_ bundledActions: [BundledAction],
                              stopOnFailure: Bool = false,
                              parallel: Bool = false) {
        let context = ActionExecutionContext(
            source: .bundled(parentAction: "manual_bundle"),
            additionalInfo: ["bundle_count": bundledActions.count]
        )
        
        // Create parameters for the bundle plugin
        var parameters: [String: AnyCodable] = [:]
        
        // Encode bundled actions
        if let data = try? JSONEncoder().encode(bundledActions) {
            parameters["bundle_actions"] = AnyCodable(data)
        } else {
            // Fallback to dictionary representation
            let actionsArray = bundledActions.map { action -> [String: Any] in
                var dict: [String: Any] = [:]
                dict["actionIdentifier"] = action.actionIdentifier
                dict["parameters"] = action.parameters
                dict["delayAfter"] = action.delayAfter
                dict["conditionData"] = action.conditionData
                return dict
            }
            parameters["bundle_actions"] = AnyCodable(actionsArray)
        }
        
        parameters["stop_on_failure"] = AnyCodable(stopOnFailure)
        parameters["parallel_execution"] = AnyCodable(parallel)
        
        // Execute through the bundle plugin
        executeAction("com.mousegestures.bundle.execute_bundle",
                     parameters: ActionParameters(values: parameters),
                     context: context)
    }
    
    /// Execute a long press gesture
    func executeLongPressGesture(_ gesture: Gesture) {
        guard gesture.timing.longPressEnabled else {
            executeGesture(gesture)
            return
        }
        
        let context = ActionExecutionContext(
            source: .longPress,
            gesture: gesture,
            modifiers: gesture.modifiers
        )
        
        if let longPressId = gesture.longPressActionIdentifier {
            let params = ActionParameters(values: gesture.longPressParameters ?? gesture.parameters)
            executeAction(longPressId, parameters: params, context: context)
        } else {
            executeAction(gesture.actionIdentifier, parameters: ActionParameters(values: gesture.parameters), context: context)
        }
    }
    
    // MARK: - Core Execution Logic
    
    private func executeAction(_ actionId: String, 
                              parameters: ActionParameters,
                              context: ActionExecutionContext) {
        // Check debouncing
        if enableDebouncing {
            let actionKey = "\(actionId)_\(context.source)"
            guard debouncer.shouldExecute(action: actionKey) else {
                log.log("Action debounced: \(actionId)")
                return
            }
        }
        
        executeActionWithoutDebounce(actionId, parameters: parameters, context: context)
    }
    
    private func executeActionWithoutDebounce(_ actionId: String,
                                             parameters: ActionParameters,
                                             context: ActionExecutionContext) {
        let executionId = UUID()
        let startTime = Date()
        
        // Track active execution
        executionQueue.async(flags: .barrier) {
            self.activeExecutions.insert(executionId)
        }
        
        // Notify delegates - will execute
        notifyDelegatesWillExecute(actionId: actionId, context: context)
        
        // Log execution start
        log.log("Executing action: \(actionId) from source: \(context.source)")
        
        // Execute through the plugin system
        do {
            try pluginManager.executeAction(identifier: actionId, parameters: parameters)
            
            let result = ActionExecutionResult(
                success: true,
                actionId: actionId,
                executionTime: Date().timeIntervalSince(startTime)
            )
            
            handleExecutionSuccess(actionId: actionId, result: result, context: context, executionId: executionId)
        } catch {
            handleExecutionFailure(actionId: actionId, error: error, context: context, executionId: executionId, startTime: startTime)
        }
    }
    
    private func handleExecutionSuccess(actionId: String,
                                       result: ActionExecutionResult,
                                       context: ActionExecutionContext,
                                       executionId: UUID) {
        // Provide haptic feedback
        provideHapticFeedback()
        
        // Update statistics
        executionStats.recordSuccess(actionId: actionId, executionTime: result.executionTime)
        
        // Record execution
        recordExecution(actionId: actionId, result: result, context: context)
        
        // Notify delegates - did execute
        notifyDelegatesDidExecute(actionId: actionId, result: result, context: context)
        
        // Remove from active executions
        executionQueue.async(flags: .barrier) {
            self.activeExecutions.remove(executionId)
        }
        
        log.log("Successfully executed action: \(actionId) in \(result.executionTime)s")
    }
    
    private func handleExecutionFailure(actionId: String,
                                       error: Error,
                                       context: ActionExecutionContext,
                                       executionId: UUID,
                                       startTime: Date) {
        let result = ActionExecutionResult(
            success: false,
            actionId: actionId,
            error: error,
            executionTime: Date().timeIntervalSince(startTime)
        )
        
        // Update statistics
        executionStats.recordFailure(actionId: actionId, error: error)
        
        // Record execution
        recordExecution(actionId: actionId, result: result, context: context)
        
        // Notify delegates - did fail
        notifyDelegatesDidFail(actionId: actionId, error: error, context: context)
        
        // Remove from active executions
        executionQueue.async(flags: .barrier) {
            self.activeExecutions.remove(executionId)
        }
        
        log.log("Failed to execute action: \(actionId) - Error: \(error)")
    }
    
    // MARK: - Helper Methods
    
    private func provideHapticFeedback() {
        guard enableHapticFeedback else { return }
        
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
    
    // MARK: - Execution History
    
    private func recordExecution(actionId: String, result: ActionExecutionResult, context: ActionExecutionContext) {
        let record = ActionExecutionRecord(
            id: UUID(),
            timestamp: context.timestamp,
            actionId: actionId,
            source: context.source,
            result: result,
            context: context
        )
        
        historyQueue.async {
            self.executionHistory.append(record)
            
            // Trim history if needed
            if self.executionHistory.count > self.maxHistorySize {
                self.executionHistory.removeFirst(self.executionHistory.count - self.maxHistorySize)
            }
        }
    }
    
    func getExecutionHistory(limit: Int? = nil) -> [ActionExecutionRecord] {
        return historyQueue.sync {
            if let limit = limit {
                return Array(executionHistory.suffix(limit))
            }
            return executionHistory
        }
    }
    
    func clearExecutionHistory() {
        historyQueue.async {
            self.executionHistory.removeAll()
        }
    }
    
    // MARK: - Statistics
    
    func getExecutionStatistics() -> ActionExecutionStatistics {
        return executionQueue.sync {
            return executionStats
        }
    }
    
    func resetStatistics() {
        executionQueue.async(flags: .barrier) {
            self.executionStats = ActionExecutionStatistics()
        }
    }
    
    // MARK: - Active Executions
    
    func getActiveExecutionCount() -> Int {
        return executionQueue.sync {
            return activeExecutions.count
        }
    }
    
    func isExecuting() -> Bool {
        return getActiveExecutionCount() > 0
    }
    
    // MARK: - Delegate Management
    
    func addDelegate(_ delegate: ActionExecutionDelegate) {
        delegates.append(delegate)
    }
    
    func removeDelegate(_ delegate: ActionExecutionDelegate) {
        delegates.removeAll { $0 === delegate }
    }
    
    private func notifyDelegatesWillExecute(actionId: String, context: ActionExecutionContext) {
        delegates.forEach { delegate in
            delegate.actionExecutionManager(self, willExecuteAction: actionId, context: context)
        }
    }
    
    private func notifyDelegatesDidExecute(actionId: String, result: ActionExecutionResult, context: ActionExecutionContext) {
        delegates.forEach { delegate in
            delegate.actionExecutionManager(self, didExecuteAction: actionId, result: result, context: context)
        }
    }
    
    private func notifyDelegatesDidFail(actionId: String, error: Error, context: ActionExecutionContext) {
        delegates.forEach { delegate in
            delegate.actionExecutionManager(self, didFailToExecuteAction: actionId, error: error, context: context)
        }
    }
    
    // MARK: - Configuration
    
    func setDebouncing(enabled: Bool) {
        enableDebouncing = enabled
    }
    
    func setHapticFeedback(enabled: Bool) {
        enableHapticFeedback = enabled
    }
    
    func setMaxHistorySize(_ size: Int) {
        maxHistorySize = max(0, size)
        
        // Trim history if needed
        historyQueue.async {
            if self.executionHistory.count > self.maxHistorySize {
                self.executionHistory.removeFirst(self.executionHistory.count - self.maxHistorySize)
            }
        }
    }
    

// MARK: - Supporting Types

/// Record of an action execution
struct ActionExecutionRecord {
    let id: UUID
    let timestamp: Date
    let actionId: String
    let source: ActionExecutionContext.ActionSource
    let result: ActionExecutionResult
    let context: ActionExecutionContext
}

/// Statistics about action executions
struct ActionExecutionStatistics {
    private(set) var totalExecutions: Int = 0
    private(set) var successfulExecutions: Int = 0
    private(set) var failedExecutions: Int = 0
    private(set) var averageExecutionTime: TimeInterval = 0
    private(set) var actionCounts: [String: Int] = [:]
    private(set) var errorCounts: [String: Int] = [:]
    private(set) var sourceCounts: [String: Int] = [:]
    
    mutating func recordSuccess(actionId: String, executionTime: TimeInterval) {
        totalExecutions += 1
        successfulExecutions += 1
        
        // Update average execution time
        let totalTime = averageExecutionTime * Double(totalExecutions - 1) + executionTime
        averageExecutionTime = totalTime / Double(totalExecutions)
        
        // Update action count
        actionCounts[actionId, default: 0] += 1
    }
    
    mutating func recordFailure(actionId: String, error: Error) {
        totalExecutions += 1
        failedExecutions += 1
        
        // Update action count
        actionCounts[actionId, default: 0] += 1
        
        // Update error count
        let errorKey = String(describing: type(of: error))
        errorCounts[errorKey, default: 0] += 1
    }
    
    var successRate: Double {
        guard totalExecutions > 0 else { return 0 }
        return Double(successfulExecutions) / Double(totalExecutions)
    }
}
}

// MARK: - Action Debounce

class ActionDebounce {
    static let shared = ActionDebounce()
    private var lastExecutionTimes: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 0.5
    private let queue = DispatchQueue(label: "com.mousegestures.debounce")
    
    private init() {}
    
    func shouldExecute(action: String) -> Bool {
        return queue.sync {
            if let lastTime = lastExecutionTimes[action],
               Date().timeIntervalSince(lastTime) < cooldownInterval {
                return false
            }
            lastExecutionTimes[action] = Date()
            return true
        }
    }
    
    func reset() {
        queue.sync {
            lastExecutionTimes.removeAll()
        }
    }
}
