import Cocoa
import Carbon

// MARK: - Modifier Key Detector Plugin

/// Plugin that detects modifier key presses and releases
/// Reports state changes to ActivationCoordinator for efficiency-based gating
class ModifierKeyDetectorPlugin: BaseDetectionPlugin, ActivationProvider {
    
    // MARK: - Constants
    
    public static let pluginIdentifier = "com.mousegestures.detection.modifierkey"
    
// MARK: - Properties
    
    override var identifier: String { Self.pluginIdentifier }
    override var name: String { "Modifier Key Detector" }
    override var description: String { "Detects modifier key presses (Cmd, Ctrl, Option, Shift)" }
    override var priority: Int { 200 } // High priority
    
// MARK: - Computed Settings Properties
    
    // State tracking
    private(set) var currentModifiers: NSEvent.ModifierFlags = []
    private var lastModifiers: NSEvent.ModifierFlags = []
    private var hasModifiers = false
    
    // Event monitors
    private var globalModifierMonitor: Any?
    private var localModifierMonitor: Any?
    
    // Statistics tracking
    private var modifierPressCount = 0
    private var lastEventTime: Date?
    
    // MARK: - ActivationProvider Protocol
    
    var providedActivationTypes: [ActivationType] {
        return [.modifierKey]
    }
    
    func getActivationState(for type: ActivationType) -> ActivationState? {
        guard type == .modifierKey else { return nil }
        return ActivationState(
            type: .modifierKey,
            isEngaged: hasModifiers,
            metadata: ["modifiers": currentModifiers.rawValue]
        )
    }
    
    func enableDetection(for type: ActivationType) {
        // Modifier detection is always active - nothing to enable
    }
    
    func disableDetection(for type: ActivationType) {
        // Modifier detection is always active - nothing to disable
    }
    
    func isDetectionActive(for type: ActivationType) -> Bool {
        return state == .running
    }
    
    // MARK: - Plugin-Declared Behavioral Properties
    
    func efficiencyScore(for type: ActivationType) -> Int {
        guard type == .modifierKey else { return 50 }
        return 100 // Pure event monitoring
    }
    
    func isAlwaysActive(for type: ActivationType) -> Bool {
        guard type == .modifierKey else { return false }
        return true // Event-based, very efficient
    }
    
    func isInfrastructure(for type: ActivationType) -> Bool {
        return false
    }
    
    /// Determines whether a gesture uses modifier key activation.
    /// A gesture uses modifiers when it has gesture-type activation with non-empty modifiers.
    /// This matches the same logic used in gesture detection/lookup.
    func gestureUsesActivation(_ gesture: Gesture, for type: ActivationType) -> Bool {
        guard type == .modifierKey else { return false }
        return gesture.activation.hasGesture && !gesture.modifiers.isEmpty
    }
    
    /// Precision gate validation: checks if the currently held modifiers match
    /// at least one gesture that uses the dependent type (e.g., screen zones).
    /// This prevents enabling expensive detectors when the wrong modifiers are held.
    func validateGate(for dependentType: ActivationType, gestures: [Gesture]) -> Bool {
        // If any dependent gesture has no modifier requirements, any modifier state suffices
        if gestures.contains(where: { $0.modifiers.isEmpty }) {
            return true
        }
        
        // Check if current modifiers match any of the dependent gestures
        let currentMods = currentModifiers
        for gesture in gestures {
            if currentMods.contains(gesture.modifiers) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Plugin Lifecycle
    
    override func initialize(context: DetectionContext) throws {
        try super.initialize(context: context)
        
        // Register with ActivationCoordinator
        ActivationCoordinator.shared.registerProvider(self, for: providedActivationTypes)
    }
    
    override func start() throws {
        try super.start()
        
        // Monitor modifier key changes - both global and local
        globalModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierChange(event)
        }
        
        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierChange(event)
            return event
        }
        
        // Check if modifiers are already pressed at startup
        initializeModifierState()
        
        context?.logger.log("Modifier key detection started", file: #file, function: #function, line: #line)
    }
    
    /// Initialize modifier state from current system state
    private func initializeModifierState() {
        let systemModifiers = Self.currentSystemModifiers()
        
        if !systemModifiers.isEmpty {
            context?.logger.log("Initializing with modifiers already pressed: \(modifierString(systemModifiers))", file: #file, function: #function, line: #line)
            
            currentModifiers = systemModifiers
            lastModifiers = systemModifiers
            hasModifiers = true
            
            notifyModifierEngaged()
        }
    }
    
    override func stop() {
        ActivationCoordinator.shared.pluginStopping(self)
        
        if let monitor = globalModifierMonitor {
            NSEvent.removeMonitor(monitor)
            globalModifierMonitor = nil
        }
        
        if let monitor = localModifierMonitor {
            NSEvent.removeMonitor(monitor)
            localModifierMonitor = nil
        }
        
        currentModifiers = []
        lastModifiers = []
        hasModifiers = false
        
        super.stop()
    }
    
    override func cleanup() {
        ActivationCoordinator.shared.unregisterProvider(self)
        super.cleanup()
    }
    
    // MARK: - Event Handling
    
    private func handleModifierChange(_ event: NSEvent) {
        let newModifiers = normalizeModifiers(event.modifierFlags)
        
        guard newModifiers != currentModifiers else { return }
        
        let previousModifiers = currentModifiers
        let previousHadModifiers = hasModifiers
        
        currentModifiers = newModifiers
        hasModifiers = !newModifiers.isEmpty
        
        modifierPressCount += 1
        lastEventTime = Date()
        
        if !previousHadModifiers && hasModifiers {
            modifierPressed()
        } else if previousHadModifiers && !hasModifiers {
            allModifiersReleased()
        } else if previousHadModifiers && hasModifiers {
            modifierCombinationChanged(from: previousModifiers, to: newModifiers)
        }
        
        lastModifiers = newModifiers
        
        NotificationCenter.default.post(
            name: NSNotification.Name("ModifierStateChanged"),
            object: self,
            userInfo: ["modifiers": newModifiers.rawValue]
        )
    }
    
    // MARK: - State Transitions
    
    private func modifierPressed() {
        context?.logger.log("First modifier pressed: \(modifierString(currentModifiers))", file: #file, function: #function, line: #line)
        notifyModifierEngaged()
    }
    
    private func allModifiersReleased() {
        context?.logger.log("All modifiers released", file: #file, function: #function, line: #line)
        ActivationCoordinator.shared.activationDisengaged(.modifierKey)
    }
    
    private func modifierCombinationChanged(from oldModifiers: NSEvent.ModifierFlags, to newModifiers: NSEvent.ModifierFlags) {
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Modifiers changed from \(modifierString(oldModifiers)) to \(modifierString(newModifiers))", file: #file, function: #function, line: #line)
        }
        
        ActivationCoordinator.shared.activationEngaged(.modifierKey, metadata: [
            "modifiers": newModifiers.rawValue,
            "previous": oldModifiers.rawValue
        ])
    }
    
    private func notifyModifierEngaged() {
        ActivationCoordinator.shared.activationEngaged(.modifierKey, metadata: [
            "modifiers": currentModifiers.rawValue
        ])
    }
    
    // MARK: - Helper Methods
    
    func normalizeModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        var normalized: NSEvent.ModifierFlags = []
        if flags.contains(.command) { normalized.insert(.command) }
        if flags.contains(.control) { normalized.insert(.control) }
        if flags.contains(.option) { normalized.insert(.option) }
        if flags.contains(.shift) { normalized.insert(.shift) }
        return normalized
    }
    
    public static func currentSystemModifiers() -> NSEvent.ModifierFlags {
        let flags = NSEvent.modifierFlags
        var normalized: NSEvent.ModifierFlags = []
        if flags.contains(.command) { normalized.insert(.command) }
        if flags.contains(.control) { normalized.insert(.control) }
        if flags.contains(.option) { normalized.insert(.option) }
        if flags.contains(.shift) { normalized.insert(.shift) }
        return normalized
    }
    
    private func modifierString(_ modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        return parts.joined(separator: "")
    }
    
    // MARK: - Statistics
    
    override func getStatistics() -> DetectionPluginStatistics {
        return DetectionPluginStatistics(
            eventsDetected: modifierPressCount,
            gesturesTriggered: 0,
            errorsEncountered: 0,
            timeSinceLastEvent: lastEventTime.map { Date().timeIntervalSince($0) },
            cpuUsage: 0.1,
            memoryUsage: 0,
            customStats: [
                "currentModifiers": modifierString(currentModifiers),
                "hasModifiers": hasModifiers,
            ]
        )
    }
    
    // MARK: - Configuration
    
    override func configurationView() -> NSView? {
        return nil
    }
}
