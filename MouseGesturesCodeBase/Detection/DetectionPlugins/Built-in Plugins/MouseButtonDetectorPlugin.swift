import Cocoa

// MARK: - Mouse Button Detector Plugin

/// Plugin that detects mouse button clicks and tracks button hold state.
/// Provides two functions:
/// 1. Click triggers: Match mouseDown + modifiers against gesture mouseButtonTriggers
/// 2. Hold tracking: Report which button is physically held to ActivationCoordinator,
///    enabling gated activation of dependent types (e.g., screen zones for drag gestures)
///
/// Implements ActivationProvider for the coordinator system.
class MouseButtonDetectorPlugin: BaseDetectionPlugin, ActivationProvider {
    
    // MARK: - Constants
    
    public static let pluginIdentifier = "com.mousegestures.detection.mousebutton"
    
    // MARK: - Setting Keys
    
    enum SettingKeys {
        static let requireModifiers = "requireModifiers"
        static let allowedButtons = "allowedButtons"
    }
    
    // MARK: - Properties
    
    override var identifier: String { Self.pluginIdentifier }
    override var name: String { "Mouse Button Detector" }
    override var description: String { "Detects mouse button clicks and tracks button hold state for drag gestures" }
    override var priority: Int { 160 } // Above ScreenZoneDetector (150) since it gates it
    
    // MARK: - Settings Definitions
    
    override var settingsDefinitions: [PluginSettingDefinition] {
        [
            PluginSettingDefinition(
                key: SettingKeys.requireModifiers,
                displayName: "Require Modifiers for Click Triggers",
                description: "Only detect click-triggered gestures when modifier keys are held",
                category: .detection,
                type: .toggle(label: "Enabled"),
                defaultValue: true,
                isAdvanced: false
            ),
            PluginSettingDefinition(
                key: SettingKeys.allowedButtons,
                displayName: "Allowed Buttons",
                description: "Which mouse buttons can trigger gestures",
                category: .detection,
                type: .picker(options: [
                    .init(value: "all", displayName: "All Buttons"),
                    .init(value: "extended", displayName: "Extended Only (Middle, Button 4/5)"),
                    .init(value: "middle", displayName: "Middle Button Only")
                ]),
                defaultValue: "all",
                isAdvanced: true
            )
        ]
    }
    
    // MARK: - Computed Settings
    
    private var requireModifiers: Bool {
        settings.getBool(SettingKeys.requireModifiers, default: true)
    }
    
    private var allowedButtons: String {
        settings.getString(SettingKeys.allowedButtons, default: "all")
    }
    
    private func isButtonAllowed(_ button: MouseButtonTrigger.MouseButton) -> Bool {
        switch allowedButtons {
        case "all": return true
        case "extended": return button == .middle || button == .button4 || button == .button5
        case "middle": return button == .middle
        default: return true
        }
    }
    
    // Event monitors — mouseDown for clicks + hold, mouseUp for hold release
    private var globalLeftDownMonitor: Any?
    private var globalRightDownMonitor: Any?
    private var globalOtherDownMonitor: Any?
    private var globalLeftUpMonitor: Any?
    private var globalRightUpMonitor: Any?
    private var globalOtherUpMonitor: Any?
    // Local monitors for when our app has focus
    private var localLeftDownMonitor: Any?
    private var localRightDownMonitor: Any?
    private var localOtherDownMonitor: Any?
    private var localLeftUpMonitor: Any?
    private var localRightUpMonitor: Any?
    private var localOtherUpMonitor: Any?
    
    // Detection state
    private var isMouseButtonDetectionActive = false
    
    // Button hold state — the currently held button (nil = none held)
    private(set) var heldButton: MouseButtonTrigger.MouseButton? = nil
    
    // Statistics
    private var clicksTriggered = 0
    private var holdEngagements = 0
    private var lastTriggerTime: Date?
    
    // MARK: - ActivationProvider Protocol
    
    var providedActivationTypes: [ActivationType] {
        return [.mouseButton]
    }
    
    func getActivationState(for type: ActivationType) -> ActivationState? {
        guard type == .mouseButton else { return nil }
        return ActivationState(
            type: .mouseButton,
            isEngaged: heldButton != nil,
            metadata: buildMetadata()
        )
    }
    
    func enableDetection(for type: ActivationType) {
        guard type == .mouseButton else { return }
        enableMouseButtonMonitors()
    }
    
    func disableDetection(for type: ActivationType) {
        guard type == .mouseButton else { return }
        disableMouseButtonMonitors()
    }
    
    func isDetectionActive(for type: ActivationType) -> Bool {
        guard type == .mouseButton else { return false }
        return isMouseButtonDetectionActive
    }
    
    // MARK: - Plugin-Declared Behavioral Properties
    
    func efficiencyScore(for type: ActivationType) -> Int {
        guard type == .mouseButton else { return 50 }
        return 90 // Event monitoring, efficient
    }
    
    func isAlwaysActive(for type: ActivationType) -> Bool {
        guard type == .mouseButton else { return false }
        return true // Event-based, efficient
    }
    
    func isInfrastructure(for type: ActivationType) -> Bool {
        return false
    }
    
    /// A gesture uses mouse button activation when it has either:
    /// - A mouseButtonTrigger (click-based gesture), OR
    /// - A dragModifier != .none (requires a button to be held for zone detection)
    func gestureUsesActivation(_ gesture: Gesture, for type: ActivationType) -> Bool {
        guard type == .mouseButton else { return false }
        
        // Click-trigger gestures
        if gesture.activation.hasMouseButton && gesture.mouseButtonTrigger != nil {
            return true
        }
        
        // Drag gestures: button hold + screen zone
        if gesture.activation.hasGesture && gesture.dragModifier != .none {
            return true
        }
        
        return false
    }
    
    /// Precision gate validation for dependent types (e.g., screen zones).
    /// Checks if the currently held button matches any dependent gesture's dragModifier.
    func validateGate(for dependentType: ActivationType, gestures: [Gesture]) -> Bool {
        guard let held = heldButton else { return false }
        let heldDrag = DragModifier.from(mouseButton: held)
        
        // If any dependent gesture requires the currently held button, gate is satisfied
        for gesture in gestures {
            if gesture.dragModifier == heldDrag {
                return true
            }
            // Gestures with no drag requirement don't need mouse button gating
            // (they're gated by modifiers instead), but if they're in this list
            // they have mouseButton as a gate, so any held button satisfies them
            if gesture.dragModifier == .none {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Plugin Lifecycle
    
    override func initialize(context: DetectionContext) throws {
        try super.initialize(context: context)
        ActivationCoordinator.shared.registerProvider(self, for: providedActivationTypes)
    }
    
    override func start() throws {
        try super.start()
        ActivationCoordinator.shared.rebuildDependencies()
        logActiveButtonTriggers()
    }
    
    override func stop() {
        ActivationCoordinator.shared.pluginStopping(self)
        disableMouseButtonMonitors()
        heldButton = nil
        super.stop()
    }
    
    override func cleanup() {
        ActivationCoordinator.shared.unregisterProvider(self)
        super.cleanup()
    }
    
    // MARK: - Monitor Management
    
    private func enableMouseButtonMonitors() {
        guard !isMouseButtonDetectionActive else { return }
        
        // --- mouseDown monitors (click triggers + hold tracking) ---
        globalLeftDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            self?.handleMouseDown(e, button: .left)
        }
        localLeftDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            self?.handleMouseDown(e, button: .left); return e
        }
        
        globalRightDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] e in
            self?.handleMouseDown(e, button: .right)
        }
        localRightDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] e in
            self?.handleMouseDown(e, button: .right); return e
        }
        
        globalOtherDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] e in
            let btn = Self.otherButton(from: e)
            self?.handleMouseDown(e, button: btn)
        }
        localOtherDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] e in
            let btn = Self.otherButton(from: e)
            self?.handleMouseDown(e, button: btn); return e
        }
        
        // --- mouseUp monitors (hold release tracking) ---
        globalLeftUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouseUp(button: .left)
        }
        localLeftUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] e in
            self?.handleMouseUp(button: .left); return e
        }
        
        globalRightUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseUp) { [weak self] _ in
            self?.handleMouseUp(button: .right)
        }
        localRightUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) { [weak self] e in
            self?.handleMouseUp(button: .right); return e
        }
        
        globalOtherUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseUp) { [weak self] e in
            self?.handleMouseUp(button: Self.otherButton(from: e))
        }
        localOtherUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] e in
            self?.handleMouseUp(button: Self.otherButton(from: e)); return e
        }
        
        isMouseButtonDetectionActive = true
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Mouse button monitoring ENABLED (click + hold)", file: #file, function: #function, line: #line)
        }
    }
    
    private func disableMouseButtonMonitors() {
        let monitors: [Any?] = [
            globalLeftDownMonitor, globalRightDownMonitor, globalOtherDownMonitor,
            globalLeftUpMonitor, globalRightUpMonitor, globalOtherUpMonitor,
            localLeftDownMonitor, localRightDownMonitor, localOtherDownMonitor,
            localLeftUpMonitor, localRightUpMonitor, localOtherUpMonitor
        ]
        for m in monitors { if let m = m { NSEvent.removeMonitor(m) } }
        
        globalLeftDownMonitor = nil; globalRightDownMonitor = nil; globalOtherDownMonitor = nil
        globalLeftUpMonitor = nil; globalRightUpMonitor = nil; globalOtherUpMonitor = nil
        localLeftDownMonitor = nil; localRightDownMonitor = nil; localOtherDownMonitor = nil
        localLeftUpMonitor = nil; localRightUpMonitor = nil; localOtherUpMonitor = nil
        
        if heldButton != nil {
            heldButton = nil
            ActivationCoordinator.shared.activationDisengaged(.mouseButton)
        }
        
        isMouseButtonDetectionActive = false
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Mouse button monitoring DISABLED", file: #file, function: #function, line: #line)
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleMouseDown(_ event: NSEvent, button: MouseButtonTrigger.MouseButton) {
        // --- 1. Update button hold state ---
        let wasHeld = heldButton
        heldButton = button
        
        if wasHeld == nil {
            // First button pressed — engage coordinator
            holdEngagements += 1
            ActivationCoordinator.shared.activationEngaged(.mouseButton, metadata: buildMetadata())
            
            if context?.logger.isDebugEnabled ?? false {
                context?.logger.log("Button held: \(button.rawValue)", file: #file, function: #function, line: #line)
            }
        } else if wasHeld != button {
            // Different button now held — update coordinator metadata
            ActivationCoordinator.shared.activationEngaged(.mouseButton, metadata: buildMetadata())
        }
        
        // --- 2. Check for click-trigger gestures ---
        // NOTE: App-disabled filtering is handled centrally by DetectionPluginManager.
        
        guard isButtonAllowed(button) else { return }
        
        let modifiers = event.modifierFlags.normalized
        
        // Skip click-trigger check if no modifiers when required
        if requireModifiers && modifiers.isEmpty { return }
        
        guard let config = context?.configuration else { return }
        
        let enabledGestures = config.gestures.filter { gesture in
            gesture.isEnabled &&
            gesture.mouseButtonTrigger != nil &&
            (gesture.activationType == .mouseButton ||
             gesture.activationType == .gestureMouseButton ||
             gesture.activationType == .keyboardMouseButton ||
             gesture.activationType == .all)
        }
        
        for gesture in enabledGestures {
            guard let trigger = gesture.mouseButtonTrigger else { continue }
            
            if trigger.button == button &&
               trigger.modifiers.normalized == modifiers {
                
                clicksTriggered += 1
                lastTriggerTime = Date()
                
                context?.logger.log("✓ Mouse button trigger activated: \(trigger.displayString) -> \(gesture.actionIdentifier)", file: #file, function: #function, line: #line)
                
                let gestureContext = GestureContext(
                    source: .mouseButton(button: button, modifiers: modifiers),
                    modifiers: modifiers,
                    timestamp: Date()
                )
                
                triggerGesture(gesture, context: gestureContext)
                break // Only trigger the first match
            }
        }
    }
    
    private func handleMouseUp(button: MouseButtonTrigger.MouseButton) {
        // Only disengage if this is the button we're tracking
        guard heldButton == button else { return }
        
        heldButton = nil
        ActivationCoordinator.shared.activationDisengaged(.mouseButton)
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Button released: \(button.rawValue)", file: #file, function: #function, line: #line)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Build coordinator metadata from current hold state
    private func buildMetadata() -> [String: Any] {
        var meta: [String: Any] = [:]
        if let held = heldButton {
            meta["heldButton"] = held.rawValue
            meta["heldDragModifier"] = DragModifier.from(mouseButton: held).rawValue
        }
        return meta
    }
    
    /// Map otherMouse event to button type
    private static func otherButton(from event: NSEvent) -> MouseButtonTrigger.MouseButton {
        switch event.buttonNumber {
        case 2: return .middle
        case 3: return .button4
        default: return .button5
        }
    }
    
    private func logActiveButtonTriggers() {
        guard let config = context?.configuration else { return }
        
        let clickTriggerCount = config.gestures.filter {
            $0.mouseButtonTrigger != nil &&
            ($0.activationType == .mouseButton || $0.activationType == .gestureMouseButton ||
             $0.activationType == .keyboardMouseButton || $0.activationType == .all) &&
            $0.isEnabled
        }.count
        
        let dragGestureCount = config.gestures.filter {
            $0.isEnabled && $0.activation.hasGesture && $0.dragModifier != .none
        }.count
        
        context?.logger.log("Mouse button detection started (click triggers: \(clickTriggerCount), drag gestures: \(dragGestureCount))", file: #file, function: #function, line: #line)
    }
    
    // MARK: - Statistics
    
    override func getStatistics() -> DetectionPluginStatistics {
        return DetectionPluginStatistics(
            eventsDetected: clicksTriggered + holdEngagements,
            gesturesTriggered: clicksTriggered,
            errorsEncountered: 0,
            timeSinceLastEvent: lastTriggerTime.map { Date().timeIntervalSince($0) },
            cpuUsage: 0.1,
            memoryUsage: 0,
            customStats: [
                "clicksTriggered": clicksTriggered,
                "holdEngagements": holdEngagements,
                "heldButton": heldButton?.rawValue ?? "none"
            ]
        )
    }
}
