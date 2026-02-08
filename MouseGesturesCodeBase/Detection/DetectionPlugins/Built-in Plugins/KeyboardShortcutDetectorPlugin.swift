import Cocoa
import Carbon

// MARK: - Plugin-Specific Types

/// Keyboard trigger configuration (owned by this plugin)
struct KeyboardTrigger: Codable, Equatable {
    var keyCode: CGKeyCode
    var modifiers: NSEvent.ModifierFlags
    var displayString: String // For display in UI

    init(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags, displayString: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayString = displayString
    }
    
    /// Helper to create display string from key code and modifiers
    static func createDisplayString(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> String {
        let modStr = modifiers.symbolString
        return "\(modStr)\(keyCode.displayString)"
    }
}

// MARK: - Keyboard Shortcut Detector Plugin

/// Plugin that detects keyboard shortcuts
/// Implements ActivationProvider for the coordinator system
///
/// NOTE: This plugin does NOT track modifier state — that is the responsibility
/// of ModifierKeyDetectorPlugin. This plugin only monitors keyDown events and
/// reads modifiers from each event directly.
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
    
    // Event monitors — keyDown only (modifier tracking is ModifierKeyDetectorPlugin's job)
    private var globalKeyboardMonitor: Any?
    private var localKeyboardMonitor: Any?
    
    // State tracking
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
    
    // MARK: - Plugin-Declared Behavioral Properties
    
    func efficiencyScore(for type: ActivationType) -> Int {
        guard type == .keyboardShortcut else { return 50 }
        return 95 // Event monitoring + lookup
    }
    
    func isAlwaysActive(for type: ActivationType) -> Bool {
        guard type == .keyboardShortcut else { return false }
        return true // Event-based, efficient
    }
    
    func isInfrastructure(for type: ActivationType) -> Bool {
        return false
    }
    
    // REMOVED: gestureUsesActivation - moved to ActivationMapper
    // Plugin no longer needs to understand gesture structure
    
    // MARK: - Plugin Lifecycle
    
    override func initialize(context: DetectionContext) throws {
        try super.initialize(context: context)
        
        // Register with ActivationCoordinator
        ActivationCoordinator.shared.registerProvider(self, for: providedActivationTypes)
    }
    
    override func start() throws {
        try super.start()
        
        // Monitor key presses only — both global and local
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
        // Notify coordinator that this plugin is stopping
        ActivationCoordinator.shared.pluginStopping(self)
        
        // Remove key monitors
        if let monitor = globalKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyboardMonitor = nil
        }
        
        if let monitor = localKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyboardMonitor = nil
        }
        
        // Reset state
        lastKeyPressTime = nil
        lastTriggeredShortcut = nil
        
        super.stop()
    }
    
    override func cleanup() {
        ActivationCoordinator.shared.unregisterProvider(self)
        super.cleanup()
    }
    
    // MARK: - Event Handlers
    
    private func handleKeyPress(_ event: NSEvent) -> Bool {
        // Prevent double-triggering
        if doubleTapPreventionEnabled,
           let lastTime = lastKeyPressTime,
           Date().timeIntervalSince(lastTime) < preventionInterval {
            return false
        }
        
        // NOTE: App-disabled filtering is handled centrally by DetectionPluginManager
        // in its detectionPlugin(_:didDetectGesture:context:) delegate method.
        // This plugin only reports what it detects.
        
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.normalized
        
        guard let config = context?.configuration else { return false }
        
        // First, check for profile keyboard shortcuts (these are global and take priority)
        for profile in config.profiles {
            if let trigger = profile.keyboardShortcut,
               trigger.keyCode == CGKeyCode(keyCode) &&
               trigger.modifiers.normalized == modifiers {
                
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
        // Use ActivationMapper to determine which gestures use keyboard shortcuts
        let enabledKeyboardGestures = config.gestures.filter {
            $0.isEnabled &&
            $0.keyboardTrigger != nil &&
            ActivationMapper.shared.activationTypes(for: $0).contains(.keyboardShortcut)
        }
        
        // Skip if no keyboard shortcuts are configured
        guard !enabledKeyboardGestures.isEmpty else { return false }
        
        // Check if this key combination matches any gesture's keyboard trigger
        for gesture in enabledKeyboardGestures {
            guard let trigger = gesture.keyboardTrigger else { continue }
            
            if trigger.keyCode == CGKeyCode(keyCode) &&
               trigger.modifiers.normalized == modifiers {
                
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
    // Modifier normalization uses shared NSEvent.ModifierFlags.normalized
    // from Extensions.swift.
    
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
                   gesture.isEnabled,
                   ActivationMapper.shared.activationTypes(for: gesture).contains(.keyboardShortcut) {
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
                "profileSwitches": profileSwitches
            ]
        )
    }
}
