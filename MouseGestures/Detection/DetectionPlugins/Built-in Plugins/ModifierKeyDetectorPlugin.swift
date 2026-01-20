import Cocoa
import Carbon

// MARK: - Modifier Key Detector Plugin

/// Plugin that detects modifier key presses and releases
class ModifierKeyDetectorPlugin: BaseDetectionPlugin {
    
    // MARK: - Constants
    
    public static let pluginIdentifier = "com.mousegestures.detection.modifierkey"
    
    // MARK: - Setting Keys
    
    enum SettingKeys {
        static let cooldownPeriod = "cooldownPeriod"
        static let enableCooldown = "enableCooldown"
    }
    
    // MARK: - Properties
    
    override var identifier: String { Self.pluginIdentifier }
    override var name: String { "Modifier Key Detector" }
    override var description: String { "Detects modifier key presses (Cmd, Ctrl, Option, Shift)" }
    override var priority: Int { 200 } // High priority
    
    // MARK: - Settings Definitions
    
    override var settingsDefinitions: [PluginSettingDefinition] {
        [
            PluginSettingDefinition(
                key: SettingKeys.enableCooldown,
                displayName: "Enable Cooldown",
                description: "Prevent rapid re-triggering of gestures after modifier release",
                category: .detection,
                type: .toggle(label: "Enabled"),
                defaultValue: true,
                isAdvanced: false
            ),
            PluginSettingDefinition(
                key: SettingKeys.cooldownPeriod,
                displayName: "Cooldown Duration",
                description: "Time to wait before allowing new gestures (in seconds)",
                category: .detection,
                type: .slider(min: 0.1, max: 2.0, step: 0.1, unit: "sec"),
                defaultValue: 0.5,
                isAdvanced: true,
                dependsOn: .init(key: SettingKeys.enableCooldown, condition: .isTrue)
            )
        ]
    }
    
    // MARK: - Computed Settings Properties
    
    private var cooldownPeriod: TimeInterval {
        settings.getDouble(SettingKeys.cooldownPeriod, default: 0.5)
    }
    
    private var cooldownEnabled: Bool {
        settings.getBool(SettingKeys.enableCooldown, default: true)
    }
    
    // State tracking
    private(set) var currentModifiers: NSEvent.ModifierFlags = []
    private var lastModifiers: NSEvent.ModifierFlags = []
    private var hasModifiers = false
    
    // Cooldown tracking
    private var lastActionTime: Date?
    
    // Event monitors
    private var globalModifierMonitor: Any?
    private var localModifierMonitor: Any?
    
    // Statistics tracking
    private var modifierPressCount = 0
    private var lastEventTime: Date?
    
    // MARK: - Plugin Lifecycle
    
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
        // This handles the case where the user holds modifiers before detection starts
        initializeModifierState()
        
        context?.logger.log("Modifier key detection started", file: #file, function: #function, line: #line)
    }
    
    /// Initialize modifier state from current system state
    /// Handles case where modifiers are already pressed when detection starts
    private func initializeModifierState() {
        let systemModifiers = Self.currentSystemModifiers()
        
        if !systemModifiers.isEmpty {
            context?.logger.log("Initializing with modifiers already pressed: \(modifierString(systemModifiers))", file: #file, function: #function, line: #line)
            
            // Set current state
            currentModifiers = systemModifiers
            lastModifiers = systemModifiers
            hasModifiers = true
            
            // Enable mouse tracking since modifiers are held
            modifierPressed()
        }
    }
    
    override func stop() {
        // Remove event monitors
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
        lastModifiers = []
        hasModifiers = false
        lastActionTime = nil
        
        super.stop()
    }
    
    // MARK: - Event Handling
    
    private func handleModifierChange(_ event: NSEvent) {
        let newModifiers = normalizeModifiers(event.modifierFlags)
        
        // Check if modifiers actually changed
        guard newModifiers != currentModifiers else { return }
        
        // Store previous state
        let previousModifiers = currentModifiers
        let previousHadModifiers = hasModifiers
        
        // Update current state
        currentModifiers = newModifiers
        hasModifiers = !newModifiers.isEmpty
        
        // Update statistics
        modifierPressCount += 1
        lastEventTime = Date()
        
        // Detect state transitions
        if !previousHadModifiers && hasModifiers {
            // First modifier pressed
            modifierPressed()
        } else if previousHadModifiers && !hasModifiers {
            // All modifiers released
            allModifiersReleased()
        } else if previousHadModifiers && hasModifiers {
            // Modifier combination changed
            modifierCombinationChanged(from: previousModifiers, to: newModifiers)
        }
        
        lastModifiers = newModifiers
    }
    
    // MARK: - State Transitions
    
    private func modifierPressed() {
        context?.logger.log("First modifier pressed: \(modifierString(currentModifiers))", file: #file, function: #function, line: #line)
        
        // Enable mouse tracking in zone detector
        context?.pluginManager?.enableMouseTracking()
        
        // Notify other plugins through shared state
        notifyModifierStateChange()
    }
    
    private func allModifiersReleased() {
        context?.logger.log("All modifiers released", file: #file, function: #function, line: #line)
        
        // Disable mouse tracking if not dragging
        if let zonePlugin = context?.pluginManager?.getPlugin(ScreenZoneDetectorPlugin.pluginIdentifier) as? ScreenZoneDetectorPlugin {
            if zonePlugin.dragState == .none {
                context?.pluginManager?.disableMouseTracking()
            }
        }
        
        // Mark action executed for cooldown
        markActionExecuted()
        
        // Notify other plugins
        notifyModifierStateChange()
    }
    
    private func modifierCombinationChanged(from oldModifiers: NSEvent.ModifierFlags, to newModifiers: NSEvent.ModifierFlags) {
        if context?.logger.isDebugEnabled ?? false {
            if context?.logger.isDebugEnabled == true {
                context?.logger.log("Modifiers changed from \(modifierString(oldModifiers)) to \(modifierString(newModifiers))", file: #file, function: #function, line: #line)
            }
        }
        
        // Notify other plugins
        notifyModifierStateChange()
    }
    
    // MARK: - Helper Methods
    
    /// Normalize modifier flags to only include the ones we care about
    func normalizeModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        var normalized: NSEvent.ModifierFlags = []
        if flags.contains(.command) { normalized.insert(.command) }
        if flags.contains(.control) { normalized.insert(.control) }
        if flags.contains(.option) { normalized.insert(.option) }
        if flags.contains(.shift) { normalized.insert(.shift) }
        return normalized
    }
    
    /// Get current system modifiers in real-time
    public static func currentSystemModifiers() -> NSEvent.ModifierFlags {
        let flags = NSEvent.modifierFlags
        var normalized: NSEvent.ModifierFlags = []
        if flags.contains(.command) { normalized.insert(.command) }
        if flags.contains(.control) { normalized.insert(.control) }
        if flags.contains(.option) { normalized.insert(.option) }
        if flags.contains(.shift) { normalized.insert(.shift) }
        return normalized
    }
    
    /// Convert modifiers to human-readable string
    private func modifierString(_ modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        return parts.joined(separator: "")
    }
    
    /// Mark that an action was executed for cooldown tracking
    func markActionExecuted() {
        lastActionTime = Date()
    }
    
    /// Check if we're in cooldown period
    var isInCooldownPeriod: Bool {
        guard cooldownEnabled else { return false }
        guard let lastTime = lastActionTime else { return false }
        return Date().timeIntervalSince(lastTime) < cooldownPeriod
    }
    
    /// Notify other plugins of modifier state change
    private func notifyModifierStateChange() {
        // This could be expanded to a formal notification system
        // For now, other plugins can query current state directly
    }
    
    // MARK: - Statistics
    
    override func getStatistics() -> DetectionPluginStatistics {
        return DetectionPluginStatistics(
            eventsDetected: modifierPressCount,
            gesturesTriggered: 0, // This plugin doesn't directly trigger gestures
            errorsEncountered: 0,
            timeSinceLastEvent: lastEventTime.map { Date().timeIntervalSince($0) },
            cpuUsage: 0.1, // Minimal CPU usage
            memoryUsage: 0,
            customStats: [
                "currentModifiers": modifierString(currentModifiers),
                "hasModifiers": hasModifiers,
                "inCooldown": isInCooldownPeriod
            ]
        )
    }
    
    // MARK: - Configuration
    
    override func configurationView() -> NSView? {
        // Could provide UI for cooldown period adjustment
        return nil
    }
}
