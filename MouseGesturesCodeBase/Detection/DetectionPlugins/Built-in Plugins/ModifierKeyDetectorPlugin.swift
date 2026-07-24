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
    override var priority: Int { 200 }
    override var triggerIcon: String { "command.square" }
    override var triggerTitle: String { "Modifier Keys" }
    override var triggerDescription: String { "Require modifier keys to be held" }
    override var providesTriggerUI: Bool { true }

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
        guard type == .modifierKey else { return }
        enableModifierMonitors()
    }

    func disableDetection(for type: ActivationType) {
        guard type == .modifierKey else { return }
        disableModifierMonitors()
    }

    func isDetectionActive(for type: ActivationType) -> Bool {
        guard type == .modifierKey else { return false }
        return globalModifierMonitor != nil
    }

    // MARK: - Plugin-Declared Behavioral Properties

    func efficiencyScore(for type: ActivationType) -> Int {
        guard type == .modifierKey else { return 50 }
        return 100 // Pure event monitoring
    }

    func isAlwaysActive(for type: ActivationType) -> Bool {
        return false // Gated by activation coordinator based on gesture requirements
    }

    func isInfrastructure(for type: ActivationType) -> Bool {
        return false
    }

    // REMOVED: gestureUsesActivation - moved to ActivationMapper
    // Plugin no longer needs to understand gesture structure

    /// Provide current modifier state for precision gate validation.
    /// The ActivationMapper will use this to check gesture requirements.
    func getGateValidationMetadata() -> [String: Any] {
        return ["modifiers": currentModifiers.rawValue]
    }

    // MARK: - Plugin Lifecycle

    override func initialize(context: DetectionContext) throws {
        try super.initialize(context: context)

        // Register with ActivationCoordinator
        ActivationCoordinator.shared.registerProvider(self, for: providedActivationTypes)
    }

    override func start() throws {
        try super.start()

        // Detection is now enabled/disabled via ActivationCoordinator
        // which calls enableDetection/disableDetection.
        ActivationCoordinator.shared.rebuildDependencies()

        context?.logger.log("Modifier key detector started (waiting for activation)", file: #file, function: #function, line: #line)
    }

    private func enableModifierMonitors() {
        guard globalModifierMonitor == nil else { return }

        // Monitor modifier key changes - both global and local
        globalModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] _ in
            self?.handleModifierChange()
        }

        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierChange()
            return event
        }

        // Check if modifiers are already pressed when monitors enable
        initializeModifierState()

        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Modifier key monitoring ENABLED", file: #file, function: #function, line: #line)
        }
    }

    /// Initialize modifier state from current system state
    private func initializeModifierState() {
        let systemModifiers = NSEvent.ModifierFlags.currentHardware

        if !systemModifiers.isEmpty {
            context?.logger.log("Initializing with modifiers already pressed: \(systemModifiers.symbolString)", file: #file, function: #function, line: #line)

            currentModifiers = systemModifiers
            lastModifiers = systemModifiers
            hasModifiers = true

            notifyModifierEngaged()
        }
    }

    override func stop() {
        ActivationCoordinator.shared.pluginStopping(self)
        disableModifierMonitors()
        super.stop()
    }

    private func disableModifierMonitors() {
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

        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Modifier key monitoring DISABLED", file: #file, function: #function, line: #line)
        }
    }

    override func cleanup() {
        ActivationCoordinator.shared.unregisterProvider(self)
        super.cleanup()
    }

    // MARK: - Event Handling

    private func handleModifierChange() {
        // Re-query true hardware state instead of trusting the flagsChanged
        // event's own flags — see NSEvent.ModifierFlags.currentHardware and
        // clearModifierStateContamination(from:) for why this alone isn't
        // sufficient and what actually closes the gap on the write side.
        let newModifiers = NSEvent.ModifierFlags.currentHardware

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
        context?.logger.log("First modifier pressed: \(currentModifiers.symbolString)", file: #file, function: #function, line: #line)
        notifyModifierEngaged()
    }

    private func allModifiersReleased() {
        context?.logger.log("All modifiers released", file: #file, function: #function, line: #line)
        ActivationCoordinator.shared.activationDisengaged(.modifierKey)
    }

    private func modifierCombinationChanged(from oldModifiers: NSEvent.ModifierFlags, to newModifiers: NSEvent.ModifierFlags) {
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Modifiers changed from \(oldModifiers.symbolString) to \(newModifiers.symbolString)", file: #file, function: #function, line: #line)
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
    // Modifier normalization, system query, and display use shared
    // NSEvent.ModifierFlags extensions in Extensions.swift.

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
                "currentModifiers": currentModifiers.symbolString,
                "hasModifiers": hasModifiers
            ]
        )
    }

    // MARK: - Configuration

    override func configurationView() -> NSView? {
        return nil
    }
}
