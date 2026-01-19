import Cocoa

// MARK: - Mouse Button Detector Plugin

/// Plugin that detects mouse button clicks with modifiers
class MouseButtonDetectorPlugin: BaseDetectionPlugin {
    
    // MARK: - Constants
    
    public static let pluginIdentifier = "com.mousegestures.detection.mousebutton"
    
    // MARK: - Properties
    
    override var identifier: String { Self.pluginIdentifier }
    override var name: String { "Mouse Button Detector" }
    override var description: String { "Detects mouse button clicks combined with modifier keys" }
    override var priority: Int { 90 } // Medium-low priority
    
    // Event monitors
    private var leftMouseMonitor: Any?
    private var rightMouseMonitor: Any?
    private var otherMouseMonitor: Any?
    
    // Statistics
    private var buttonsTriggered = 0
    private var lastTriggerTime: Date?
    
    // MARK: - Plugin Lifecycle
    
    override func start() throws {
        try super.start()
        
        // Monitor mouse button clicks for modifier + button triggers
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
        
        // Log active mouse button triggers
        logActiveButtonTriggers()
    }
    
    override func stop() {
        // Remove all monitors
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
        
        super.stop()
    }
    
    // MARK: - Event Handlers
    
    private func handleMouseButtonClick(_ event: NSEvent, button: MouseButtonTrigger.MouseButton) {
        // Check if mouse button triggers should be processed (app not disabled)
        guard !(context?.pluginManager?.isCurrentAppDisabled() ?? false) else {
            return
        }
        
        // Get current modifiers
        let modifiers = normalizeModifiers(event.modifierFlags)
        
        // Skip if no modifiers (we don't want to trigger on plain clicks)
        guard !modifiers.isEmpty else { return }
        
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
                
                context?.logger.log("✓ Mouse button trigger activated: \(trigger.displayString) -> \(gesture.actionIdentifier)", file: #file, function: #function, line: #line)
                
                // Create gesture context
                let gestureContext = GestureContext(
                    source: .mouseButton(button: button, modifiers: modifiers),
                    modifiers: modifiers,
                    timestamp: Date()
                )
                
                // Trigger the gesture
                triggerGesture(gesture, context: gestureContext)
                
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
                "buttonsTriggered": buttonsTriggered
            ]
        )
    }
}
