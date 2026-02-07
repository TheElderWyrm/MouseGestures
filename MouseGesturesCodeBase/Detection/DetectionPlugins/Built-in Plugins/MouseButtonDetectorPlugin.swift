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
    
    // Event monitors — consolidated: 1 global down, 1 local down, 1 global up, 1 local up
    private var globalDownMonitor: Any?
    private var localDownMonitor: Any?
    private var globalUpMonitor: Any?
    private var localUpMonitor: Any?
    
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
        if gesture.activation.hasMouseButton && gesture.mouseButtonTrigger != nil { return true }
        if gesture.activation.hasGesture && gesture.dragModifier != .none { return true }
        return false
    }
    
    /// Precision gate validation for dependent types (e.g., screen zones).
    /// Checks if the currently held button matches any dependent gesture's dragModifier.
    /// This prevents screen zones from activating during drags when no matching drag gesture exists.
    func validateGate(for dependentType: ActivationType, gestures: [Gesture]) -> Bool {
        guard dependentType == .screenZone else { return true }
        guard let held = heldButton else { return false }
        let heldDrag = DragModifier.from(mouseButton: held)
        
        // Only enable screen zones if:
        // 1. A gesture requires this specific drag modifier, OR
        // 2. A gesture requires no drag (dragModifier == .none)
        for gesture in gestures {
            if gesture.dragModifier == heldDrag { return true }
            if gesture.dragModifier == .none { return true }
        }
        
        // No matching drag gestures found - don't enable screen zones
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Gate validation FAILED: held button \(held.rawValue) doesn't match any screen zone gesture requirements", file: #file, function: #function, line: #line)
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
    
    private static let downEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    private static let upEvents: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
    
    private func enableMouseButtonMonitors() {
        guard !isMouseButtonDetectionActive else { return }
        
        globalDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.downEvents) { [weak self] e in
            self?.handleMouseDown(e)
        }
        localDownMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.downEvents) { [weak self] e in
            self?.handleMouseDown(e); return e
        }
        
        globalUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.upEvents) { [weak self] e in
            self?.handleMouseUp(e)
        }
        localUpMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.upEvents) { [weak self] e in
            self?.handleMouseUp(e); return e
        }
        
        isMouseButtonDetectionActive = true
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Mouse button monitoring ENABLED (4 monitors)", file: #file, function: #function, line: #line)
        }
        
        // Check if a button is already physically held when monitors enable.
        // This handles the case where the user holds a mouse button before
        // satisfying the gate (e.g., holds right-click then presses ⌘).
        initializeButtonState()
    }
    
    /// Detect already-held buttons when monitoring starts (mirrors ModifierKeyDetector's
    /// initializeModifierState). Uses NSEvent.pressedMouseButtons for direct OS query.
    private func initializeButtonState() {
        let pressed = NSEvent.pressedMouseButtons
        guard pressed != 0 else { return }
        
        // Determine which button is held (priority: right > middle > left,
        // since left-click is rarely used as a drag gesture trigger)
        let button: MouseButtonTrigger.MouseButton
        if pressed & (1 << 1) != 0 { button = .right }
        else if pressed & (1 << 2) != 0 { button = .middle }
        else if pressed & (1 << 0) != 0 { button = .left }
        else if pressed & (1 << 3) != 0 { button = .button4 }
        else if pressed & (1 << 4) != 0 { button = .button5 }
        else { return }
        
        context?.logger.log("Initializing with button already held: \(button.rawValue)", file: #file, function: #function, line: #line)
        
        heldButton = button
        holdEngagements += 1
        ActivationCoordinator.shared.activationEngaged(.mouseButton, metadata: buildMetadata())
    }
    
    private func disableMouseButtonMonitors() {
        guard isMouseButtonDetectionActive else { return }
        
        for m in [globalDownMonitor, localDownMonitor, globalUpMonitor, localUpMonitor] {
            if let m = m { NSEvent.removeMonitor(m) }
        }
        globalDownMonitor = nil; localDownMonitor = nil
        globalUpMonitor = nil; localUpMonitor = nil
        
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
    
    private func handleMouseDown(_ event: NSEvent) {
        let button = Self.buttonFrom(event)
        
        // --- 1. Update button hold state ---
        let wasHeld = heldButton
        heldButton = button
        
        if wasHeld == nil {
            holdEngagements += 1
            ActivationCoordinator.shared.activationEngaged(.mouseButton, metadata: buildMetadata())
            
            if context?.logger.isDebugEnabled ?? false {
                context?.logger.log("Button held: \(button.rawValue)", file: #file, function: #function, line: #line)
            }
        } else if wasHeld != button {
            ActivationCoordinator.shared.activationEngaged(.mouseButton, metadata: buildMetadata())
        }
        
        // --- 2. Check for click-trigger gestures ---
        // NOTE: App-disabled filtering is handled centrally by DetectionPluginManager.
        
        guard isButtonAllowed(button) else { return }
        
        let modifiers = event.modifierFlags.normalized
        if requireModifiers && modifiers.isEmpty { return }
        
        guard let config = context?.configuration else { return }
        
        let enabledGestures = config.gestures.filter { g in
            g.isEnabled && g.mouseButtonTrigger != nil &&
            (g.activationType == .mouseButton || g.activationType == .gestureMouseButton ||
             g.activationType == .keyboardMouseButton || g.activationType == .all)
        }
        
        for gesture in enabledGestures {
            guard let trigger = gesture.mouseButtonTrigger else { continue }
            if trigger.button == button && trigger.modifiers.normalized == modifiers {
                clicksTriggered += 1
                lastTriggerTime = Date()
                
                context?.logger.log("✓ Mouse button trigger: \(trigger.displayString) -> \(gesture.actionIdentifier)", file: #file, function: #function, line: #line)
                
                triggerGesture(gesture, context: GestureContext(
                    source: .mouseButton(button: button, modifiers: modifiers),
                    modifiers: modifiers, timestamp: Date()
                ))
                break
            }
        }
    }
    
    private func handleMouseUp(_ event: NSEvent) {
        let button = Self.buttonFrom(event)
        guard heldButton == button else { return }
        
        heldButton = nil
        ActivationCoordinator.shared.activationDisengaged(.mouseButton)
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Button released: \(button.rawValue)", file: #file, function: #function, line: #line)
        }
    }
    
    // MARK: - Helper Methods
    
    private func buildMetadata() -> [String: Any] {
        var meta: [String: Any] = [:]
        if let held = heldButton {
            meta["heldButton"] = held.rawValue
            meta["heldDragModifier"] = DragModifier.from(mouseButton: held).rawValue
        }
        return meta
    }
    
    /// Determine which button from any mouseDown/mouseUp event
    private static func buttonFrom(_ event: NSEvent) -> MouseButtonTrigger.MouseButton {
        switch event.type {
        case .leftMouseDown, .leftMouseUp: return .left
        case .rightMouseDown, .rightMouseUp: return .right
        default: // otherMouseDown/Up
            switch event.buttonNumber {
            case 2: return .middle
            case 3: return .button4
            default: return .button5
            }
        }
    }
    
    private func logActiveButtonTriggers() {
        guard let config = context?.configuration else { return }
        
        let clickCount = config.gestures.filter {
            $0.mouseButtonTrigger != nil && $0.isEnabled &&
            ($0.activationType == .mouseButton || $0.activationType == .gestureMouseButton ||
             $0.activationType == .keyboardMouseButton || $0.activationType == .all)
        }.count
        
        let dragCount = config.gestures.filter {
            $0.isEnabled && $0.activation.hasGesture && $0.dragModifier != .none
        }.count
        
        context?.logger.log("Mouse button detection started (clicks: \(clickCount), drag gestures: \(dragCount))", file: #file, function: #function, line: #line)
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
