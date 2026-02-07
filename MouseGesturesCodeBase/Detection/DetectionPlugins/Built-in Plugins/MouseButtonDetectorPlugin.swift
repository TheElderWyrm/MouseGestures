import Cocoa

// MARK: - Mouse Button Detector Plugin

/// Plugin that detects mouse button clicks with modifiers
/// Implements ActivationProvider for the coordinator system
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
    override var description: String { "Detects mouse button clicks combined with modifier keys" }
    override var priority: Int { 90 } // Medium-low priority
    
    // MARK: - Settings Definitions
    
    override var settingsDefinitions: [PluginSettingDefinition] {
        [
            PluginSettingDefinition(
                key: SettingKeys.requireModifiers,
                displayName: "Require Modifiers",
                description: "Only detect mouse buttons when modifier keys are held",
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
        case "all":
            return true
        case "extended":
            return button == .middle || button == .button4 || button == .button5
        case "middle":
            return button == .middle
        default:
            return true
        }
    }
    
    // Event monitors
    private var leftMouseMonitor: Any?
    private var rightMouseMonitor: Any?
    private var otherMouseMonitor: Any?
    
    // Detection state
    private var isMouseButtonDetectionActive = false
    
    // State tracking
    private var lastTriggeredButton: MouseButtonTrigger.MouseButton?
    
    // Statistics
    private var buttonsTriggered = 0
    private var lastTriggerTime: Date?
    
    // MARK: - ActivationProvider Protocol
    
    var providedActivationTypes: [ActivationType] {
        return [.mouseButton]
    }
    
    func getActivationState(for type: ActivationType) -> ActivationState? {
        guard type == .mouseButton else { return nil }
        return ActivationState(
            type: .mouseButton,
            isEngaged: lastTriggeredButton != nil && lastTriggerTime != nil,
            metadata: ["lastButton": lastTriggeredButton?.rawValue ?? "none"]
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
        return 90 // Event monitoring + lookup
    }
    
    func isAlwaysActive(for type: ActivationType) -> Bool {
        guard type == .mouseButton else { return false }
        return true // Event-based, efficient
    }
    
    func isInfrastructure(for type: ActivationType) -> Bool {
        return false
    }
    
    /// A gesture uses mouse button activation when it has a mouse button trigger
    /// and its activation type includes mouse button.
    func gestureUsesActivation(_ gesture: Gesture, for type: ActivationType) -> Bool {
        guard type == .mouseButton else { return false }
        return gesture.activation.hasMouseButton && gesture.mouseButtonTrigger != nil
    }
    
    // MARK: - Plugin Lifecycle
    
    override func initialize(context: DetectionContext) throws {
        try super.initialize(context: context)
        
        // Register with ActivationCoordinator
        ActivationCoordinator.shared.registerProvider(self, for: providedActivationTypes)
    }
    
    override func start() throws {
        try super.start()
        
        // Monitors are managed by ActivationCoordinator via enableDetection/disableDetection
        // Trigger a dependency rebuild so the coordinator enables monitors if needed
        ActivationCoordinator.shared.rebuildDependencies()
        
        logActiveButtonTriggers()
    }
    
    override func stop() {
        // Notify coordinator that this plugin is stopping
        ActivationCoordinator.shared.pluginStopping(self)
        
        // Remove all monitors
        disableMouseButtonMonitors()
        
        lastTriggeredButton = nil
        
        super.stop()
    }
    
    // MARK: - Monitor Management
    
    /// Enable mouse button monitors (called by ActivationCoordinator)
    private func enableMouseButtonMonitors() {
        guard !isMouseButtonDetectionActive else { return }
        
        leftMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseButtonClick(event, button: .left)
        }
        
        rightMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.handleMouseButtonClick(event, button: .right)
        }
        
        otherMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            let buttonNumber = event.buttonNumber
            let button: MouseButtonTrigger.MouseButton = buttonNumber == 2 ? .middle : (buttonNumber == 3 ? .button4 : .button5)
            self?.handleMouseButtonClick(event, button: button)
        }
        
        isMouseButtonDetectionActive = true
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Mouse button monitoring ENABLED", file: #file, function: #function, line: #line)
        }
    }
    
    /// Disable mouse button monitors (called by ActivationCoordinator)
    private func disableMouseButtonMonitors() {
        guard isMouseButtonDetectionActive else { return }
        
        if let monitor = leftMouseMonitor {
            NSEvent.removeMonitor(monitor)
            leftMouseMonitor = nil
        }
        
        if let monitor = rightMouseMonitor {
            NSEvent.removeMonitor(monitor)
            rightMouseMonitor = nil
        }
        
        if let monitor = otherMouseMonitor {
            NSEvent.removeMonitor(monitor)
            otherMouseMonitor = nil
        }
        
        isMouseButtonDetectionActive = false
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Mouse button monitoring DISABLED", file: #file, function: #function, line: #line)
        }
    }
    
    override func cleanup() {
        ActivationCoordinator.shared.unregisterProvider(self)
        super.cleanup()
    }
    
    // MARK: - Event Handlers
    
    private func handleMouseButtonClick(_ event: NSEvent, button: MouseButtonTrigger.MouseButton) {
        // Check if mouse button triggers should be processed (app not disabled)
        guard !(context?.pluginManager?.isCurrentAppDisabled() ?? false) else {
            return
        }
        
        // Check if this button is allowed by settings
        guard isButtonAllowed(button) else { return }
        
        // Get current modifiers
        let modifiers = normalizeModifiers(event.modifierFlags)
        
        // Skip if no modifiers when required
        if requireModifiers && modifiers.isEmpty { return }
        
        guard let config = context?.configuration else { return }
        
        // Check for matching mouse button triggers
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
               normalizeModifiers(trigger.modifiers) == modifiers {
                
                buttonsTriggered += 1
                lastTriggerTime = Date()
                lastTriggeredButton = button
                
                context?.logger.log("✓ Mouse button trigger activated: \(trigger.displayString) -> \(gesture.actionIdentifier)", file: #file, function: #function, line: #line)
                
                // Notify coordinator
                ActivationCoordinator.shared.activationEngaged(.mouseButton, metadata: [
                    "button": button.rawValue,
                    "modifiers": modifiers.rawValue,
                    "action": gesture.actionIdentifier
                ])
                
                // Create gesture context
                let gestureContext = GestureContext(
                    source: .mouseButton(button: button, modifiers: modifiers),
                    modifiers: modifiers,
                    timestamp: Date()
                )
                
                triggerGesture(gesture, context: gestureContext)
                
                // Brief disengage to allow re-triggering
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    ActivationCoordinator.shared.activationDisengaged(.mouseButton)
                }
                
                break // Only trigger the first matching gesture
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func normalizeModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        var normalized: NSEvent.ModifierFlags = []
        if flags.contains(.command) { normalized.insert(.command) }
        if flags.contains(.control) { normalized.insert(.control) }
        if flags.contains(.option) { normalized.insert(.option) }
        if flags.contains(.shift) { normalized.insert(.shift) }
        return normalized
    }
    
    private func logActiveButtonTriggers() {
        guard let config = context?.configuration else { return }
        
        let buttonTriggerCount = config.gestures.filter {
            $0.mouseButtonTrigger != nil &&
            ($0.activationType == .mouseButton || $0.activationType == .gestureMouseButton ||
             $0.activationType == .keyboardMouseButton || $0.activationType == .all) &&
            $0.isEnabled
        }.count
        
        context?.logger.log("Mouse button detection started (monitoring \(buttonTriggerCount) button triggers)", file: #file, function: #function, line: #line)
        
        if context?.logger.isDebugEnabled ?? false {
            for gesture in config.gestures {
                if let trigger = gesture.mouseButtonTrigger,
                   (gesture.activationType == .mouseButton || gesture.activationType == .gestureMouseButton ||
                    gesture.activationType == .keyboardMouseButton || gesture.activationType == .all),
                   gesture.isEnabled {
                    context?.logger.log("  - \(trigger.displayString) -> \(gesture.actionIdentifier)", file: #file, function: #function, line: #line)
                }
            }
        }
    }
    
    // MARK: - Statistics
    
    override func getStatistics() -> DetectionPluginStatistics {
        return DetectionPluginStatistics(
            eventsDetected: buttonsTriggered,
            gesturesTriggered: buttonsTriggered,
            errorsEncountered: 0,
            timeSinceLastEvent: lastTriggerTime.map { Date().timeIntervalSince($0) },
            cpuUsage: 0.1,
            memoryUsage: 0,
            customStats: [
                "buttonsTriggered": buttonsTriggered,
                "lastButton": lastTriggeredButton?.rawValue ?? "none"
            ]
        )
    }
}
