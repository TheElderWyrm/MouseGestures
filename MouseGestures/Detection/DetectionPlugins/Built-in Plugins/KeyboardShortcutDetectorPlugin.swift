import Cocoa
import Carbon

// MARK: - Keyboard Shortcut Detector Plugin

/// Plugin that detects keyboard shortcuts
/// Implements ActivationProvider for the coordinator system
class KeyboardShortcutDetectorPlugin: BaseDetectionPlugin, ActivationProvider {
    
    // MARK: - Constants
    
    public static let pluginIdentifier = "com.mousegestures.detection.keyboard"
    
    // MARK: - Setting Keys
    
    enum SettingKeys {
        static let doubleTapPrevention = "doubleTapPrevention"
        static let preventionInterval = "preventionInterval"
    }
    
    // MARK: - Properties
    
    override var identifier: String { Self.pluginIdentifier }
    override var name: String { "Keyboard Shortcut Detector" }
    override var description: String { "Detects keyboard shortcuts and key combinations" }
    override var priority: Int { 100 } // Medium priority
    
    // MARK: - Settings Definitions
    
    override var settingsDefinitions: [PluginSettingDefinition] {
        [
            PluginSettingDefinition(
                key: SettingKeys.doubleTapPrevention,
                displayName: "Prevent Double Triggering",
                description: "Ignore rapid repeated presses of the same shortcut",
                category: .detection,
                type: .toggle(label: "Enabled"),
                defaultValue: true,
                isAdvanced: false
            ),
            PluginSettingDefinition(
                key: SettingKeys.preventionInterval,
                displayName: "Double-Tap Interval",
                description: "Minimum time between repeated shortcut triggers (in seconds)",
                category: .detection,
                type: .slider(min: 0.1, max: 1.0, step: 0.1, unit: "sec"),
                defaultValue: 0.3,
                isAdvanced: true,
                dependsOn: .init(key: SettingKeys.doubleTapPrevention, condition: .isTrue)
            )
        ]
    }
    
    // MARK: - Computed Settings
    
    private var doubleTapPreventionEnabled: Bool {
        settings.getBool(SettingKeys.doubleTapPrevention, default: true)
    }
    
    private var preventionInterval: TimeInterval {
        settings.getDouble(SettingKeys.preventionInterval, default: 0.3)
    }
    
    // Event monitors
    private var globalKeyboardMonitor: Any?
    private var localKeyboardMonitor: Any?
    private var globalModifierMonitor: Any?
    private var localModifierMonitor: Any?
    
    // State tracking
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var lastKeyPressTime: Date?
    private var lastTriggeredShortcut: String?
    
    // Statistics
    private var shortcutsTriggered = 0
    private var profileSwitches = 0
    
    // MARK: - ActivationProvider Protocol
    
    var providedActivationTypes: [ActivationType] {
        return [.keyboardShortcut]
    }
    
    func getActivationState(for type: ActivationType) -> ActivationState? {
        guard type == .keyboardShortcut else { return nil }
        return ActivationState(
            type: .keyboardShortcut,
            isEngaged: lastTriggeredShortcut != nil && lastKeyPressTime != nil,
            metadata: ["lastShortcut": lastTriggeredShortcut ?? "none"]
        )
    }
    
    func enableDetection(for type: ActivationType) {
        // Keyboard shortcut detection is always active - nothing to enable
    }
    
    func disableDetection(for type: ActivationType) {
        // Keyboard shortcut detection is always active - nothing to disable
    }
    
    func isDetectionActive(for type: ActivationType) -> Bool {
        return state == .running
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
        
        // Monitor key presses - both global and local
        globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleKeyPress(event)
        }
        
        // Local monitor for when app has focus
        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let handled = self?.handleKeyPress(event), handled {
                return nil
            }
            return event
        }
        
        logActiveShortcuts()
    }
    
    override func stop() {
        // Remove all monitors
        if let monitor = globalKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyboardMonitor = nil
        }
        
        if let monitor = localKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyboardMonitor = nil
        }
        
        if let monitor = globalModifierMonitor {
            NSEvent.removeMonitor(monitor)
            globalModifierMonitor = nil
        }
        
        if let monitor = localModifierMonitor {
            NSEvent.removeMonitor(monitor)
            localModifierMonitor = nil
        }
        
        // Reset state
        currentModifiers = []
        lastKeyPressTime = nil
        lastTriggeredShortcut = nil
        
        super.stop()
    }
    
    override func cleanup() {
        ActivationCoordinator.shared.unregisterProvider(self)
        super.cleanup()
    }
    
    // MARK: - Event Handlers
    
    private func handleModifierChange(_ event: NSEvent) {
        currentModifiers = normalizeModifiers(event.modifierFlags)
    }
    
    private func handleKeyPress(_ event: NSEvent) -> Bool {
        // Prevent double-triggering
        if doubleTapPreventionEnabled,
           let lastTime = lastKeyPressTime,
           Date().timeIntervalSince(lastTime) < preventionInterval {
            return false
        }
        
        // Check if shortcuts should be processed (app not disabled)
        guard !(context?.pluginManager?.isCurrentAppDisabled() ?? false) else {
            return false
        }
        
        let keyCode = event.keyCode
        let modifiers = normalizeModifiers(event.modifierFlags)
        
        guard let config = context?.configuration else { return false }
        
        // First, check for profile keyboard shortcuts (these are global and take priority)
        for profile in config.profiles {
            if let trigger = profile.keyboardShortcut,
               trigger.keyCode == CGKeyCode(keyCode) &&
               normalizeModifiers(trigger.modifiers) == modifiers {
                
                lastKeyPressTime = Date()
                lastTriggeredShortcut = trigger.displayString
                profileSwitches += 1
                
                context?.logger.log("✓ Profile shortcut triggered: \(trigger.displayString) -> Profile '\(profile.name)'", file: #file, function: #function, line: #line)
                
                // Notify coordinator
                ActivationCoordinator.shared.activationEngaged(.keyboardShortcut, metadata: [
                    "shortcut": trigger.displayString,
                    "profileSwitch": true
                ])
                
                triggerProfileSwitch(profile)
                
                // Brief disengage to allow re-triggering
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    ActivationCoordinator.shared.activationDisengaged(.keyboardShortcut)
                }
                
                return true
            }
        }
        
        // Then check regular gesture keyboard shortcuts
        let enabledKeyboardGestures = config.gestures.filter {
            $0.isEnabled &&
            $0.keyboardTrigger != nil &&
            ($0.activationType == .keyboard ||
             $0.activationType == .both ||
             $0.activationType == .keyboardMouseButton ||
             $0.activationType == .all)
        }
        
        // Skip if no keyboard shortcuts are configured
        guard !enabledKeyboardGestures.isEmpty else { return false }
        
        // Check if this key combination matches any gesture's keyboard trigger
        for gesture in enabledKeyboardGestures {
            guard let trigger = gesture.keyboardTrigger else { continue }
            
            if trigger.keyCode == CGKeyCode(keyCode) &&
               normalizeModifiers(trigger.modifiers) == modifiers {
                
                lastKeyPressTime = Date()
                lastTriggeredShortcut = trigger.displayString
                shortcutsTriggered += 1
                
                context?.logger.log("✓ Keyboard shortcut triggered: \(trigger.displayString) -> \(gesture.actionIdentifier)", file: #file, function: #function, line: #line)
                
                // Notify coordinator
                ActivationCoordinator.shared.activationEngaged(.keyboardShortcut, metadata: [
                    "shortcut": trigger.displayString,
                    "action": gesture.actionIdentifier
                ])
                
                // Create gesture context
                let gestureContext = GestureContext(
                    source: .keyboard(trigger: trigger),
                    modifiers: modifiers,
                    timestamp: Date()
                )
                
                triggerGesture(gesture, context: gestureContext)
                
                // Brief disengage to allow re-triggering
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    ActivationCoordinator.shared.activationDisengaged(.keyboardShortcut)
                }
                
                return true
            }
        }
        
        return false
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
    
    private func logActiveShortcuts() {
        guard let config = context?.configuration else { return }
        
        let shortcutCount = config.gestures.filter {
            $0.keyboardTrigger != nil &&
            ($0.activationType == .keyboard || $0.activationType == .both || 
             $0.activationType == .keyboardMouseButton || $0.activationType == .all) &&
            $0.isEnabled
        }.count
        
        context?.logger.log("Keyboard shortcut detection started (monitoring \(shortcutCount) shortcuts)", file: #file, function: #function, line: #line)
        
        if context?.logger.isDebugEnabled ?? false {
            for gesture in config.gestures {
                if let trigger = gesture.keyboardTrigger,
                   (gesture.activationType == .keyboard || gesture.activationType == .both ||
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
            eventsDetected: shortcutsTriggered + profileSwitches,
            gesturesTriggered: shortcutsTriggered,
            errorsEncountered: 0,
            timeSinceLastEvent: lastKeyPressTime.map { Date().timeIntervalSince($0) },
            cpuUsage: 0.1,
            memoryUsage: 0,
            customStats: [
                "currentModifiers": modifierString(currentModifiers),
                "profileSwitches": profileSwitches
            ]
        )
    }
    
    private func modifierString(_ modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        return parts.joined(separator: "")
    }
}
