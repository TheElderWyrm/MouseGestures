import Cocoa

// MARK: - Screen Zone Detector Plugin
/// Plugin that detects mouse movement in screen zones.
/// Only responsible for mouse position → zone detection.
/// Button hold state comes from MouseButtonDetectorPlugin via the coordinator.
/// Modifier state comes from ModifierKeyDetectorPlugin via the coordinator.
///
/// Implements ActivationProvider for efficiency-based gating.
class ScreenZoneDetectorPlugin: BaseDetectionPlugin, ActivationProvider {
    
    // MARK: - Constants
    
    public static let pluginIdentifier = "com.mousegestures.detection.screenzone"
    
    // MARK: - Setting Keys
    
    enum SettingKeys {
        static let edgeThreshold = "edgeThreshold"
        static let cornerSize = "cornerSize"
        static let cornerBuffer = "cornerBuffer"
        static let showZoneHighlights = "showZoneHighlights"
        static let showZoneLabels = "showZoneLabels"
        static let zoneHighlightColor = "zoneHighlightColor"
        static let mouseTrackingThrottle = "mouseTrackingThrottle"
        static let enableCooldown = "enableCooldown"
        static let cooldownPeriod = "cooldownPeriod"
    }
    
    // MARK: - Properties
    
    override var identifier: String { Self.pluginIdentifier }
    override var name: String { "Screen Zone Detector" }
    override var description: String { "Detects mouse movement in screen edge and corner zones" }
    override var priority: Int { 150 } // Medium-high priority
    override var dependencies: [String] { [ModifierKeyDetectorPlugin.pluginIdentifier, MouseButtonDetectorPlugin.pluginIdentifier] }
    
    // MARK: - Settings Definitions
    
    override var settingsDefinitions: [PluginSettingDefinition] {
        [
            PluginSettingDefinition(
                key: SettingKeys.edgeThreshold,
                displayName: "Edge Threshold",
                description: "How close to screen edge to trigger detection (in pixels)",
                category: .detection,
                type: .slider(min: 5, max: 100, step: 5, unit: "px"),
                defaultValue: Double(30),
                isAdvanced: false,
                validation: .init(rule: .range(min: 5, max: 100), errorMessage: "Edge threshold must be between 5 and 100 pixels")
            ),
            PluginSettingDefinition(
                key: SettingKeys.cornerSize,
                displayName: "Corner Size",
                description: "Size of corner detection zones (in pixels)",
                category: .detection,
                type: .slider(min: 20, max: 200, step: 10, unit: "px"),
                defaultValue: Double(100),
                isAdvanced: false,
                validation: .init(rule: .range(min: 20, max: 200), errorMessage: "Corner size must be between 20 and 200 pixels")
            ),
            PluginSettingDefinition(
                key: SettingKeys.cornerBuffer,
                displayName: "Corner Buffer",
                description: "Gap between corner and edge zones (in pixels)",
                category: .detection,
                type: .slider(min: 0, max: 100, step: 5, unit: "px"),
                defaultValue: Double(50),
                isAdvanced: false,
                validation: .init(rule: .range(min: 0, max: 100), errorMessage: "Corner buffer must be between 0 and 100 pixels")
            ),
            PluginSettingDefinition(
                key: SettingKeys.showZoneHighlights,
                displayName: "Show Zone Highlights",
                description: "Display visual overlay showing detection zones",
                category: .appearance,
                type: .toggle(label: "Enabled"),
                defaultValue: false,
                isAdvanced: false
            ),
            PluginSettingDefinition(
                key: SettingKeys.showZoneLabels,
                displayName: "Show Zone Labels",
                description: "Display zone names when highlights are shown",
                category: .appearance,
                type: .toggle(label: "Enabled"),
                defaultValue: false,
                isAdvanced: false,
                dependsOn: .init(key: SettingKeys.showZoneHighlights, condition: .isTrue)
            ),
            PluginSettingDefinition(
                key: SettingKeys.zoneHighlightColor,
                displayName: "Highlight Color",
                description: "Color used for zone highlight overlay",
                category: .appearance,
                type: .color,
                defaultValue: NSColor.systemBlue.withAlphaComponent(0.3),
                isAdvanced: true,
                dependsOn: .init(key: SettingKeys.showZoneHighlights, condition: .isTrue)
            ),
            PluginSettingDefinition(
                key: SettingKeys.mouseTrackingThrottle,
                displayName: "Tracking Update Rate",
                description: "How often to check mouse position (lower = more responsive but higher CPU)",
                category: .performance,
                type: .slider(min: 8, max: 50, step: 1, unit: "ms"),
                defaultValue: 16.0, // ~60 FPS
                isAdvanced: true,
                validation: .init(rule: .range(min: 8, max: 50), errorMessage: "Update rate must be between 8 and 50 ms")
            ),
            PluginSettingDefinition(
                key: SettingKeys.enableCooldown,
                displayName: "Enable Cooldown",
                description: "Prevent rapid re-triggering of zone gestures",
                category: .detection,
                type: .toggle(label: "Enabled"),
                defaultValue: true,
                isAdvanced: false
            ),
            PluginSettingDefinition(
                key: SettingKeys.cooldownPeriod,
                displayName: "Cooldown Duration",
                description: "Time to wait before allowing new zone gestures (in seconds)",
                category: .detection,
                type: .slider(min: 0.1, max: 2.0, step: 0.1, unit: "sec"),
                defaultValue: 0.5,
                isAdvanced: true,
                dependsOn: .init(key: SettingKeys.enableCooldown, condition: .isTrue)
            )
        ]
    }
    
    // MARK: - Computed Settings Properties
    
    var edgeThreshold: CGFloat {
        settings.getCGFloat(SettingKeys.edgeThreshold, default: 30)
    }
    
    var cornerSize: CGFloat {
        settings.getCGFloat(SettingKeys.cornerSize, default: 100)
    }
    
    var cornerBuffer: CGFloat {
        settings.getCGFloat(SettingKeys.cornerBuffer, default: 50)
    }
    
    private var cooldownEnabled: Bool {
        settings.getBool(SettingKeys.enableCooldown, default: true)
    }
    
    private var cooldownPeriod: TimeInterval {
        settings.getDouble(SettingKeys.cooldownPeriod, default: 0.5)
    }
    
    // Event monitors — mouseMoved + mouseDragged for position tracking
    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?
    
    // State tracking (zone detection only — no drag state)
    private var isMouseTrackingActive = false
    private var lastTriggeredZone: ScreenZone?
    private var lastTriggeredDrag: DragModifier = .none
    private var lastTriggeredModifiers: NSEvent.ModifierFlags = []
    
    // Cooldown tracking
    private var lastActionTime: Date?
    
    // Performance optimizations
    private var lastProcessedMouseTime = Date()
    private var mouseProcessingInterval: TimeInterval {
         settings.getDouble(SettingKeys.mouseTrackingThrottle, default: 16.0) / 1000.0
     }
    
    // Zone boundary caching
    private struct ZoneBounds {
        let rect: CGRect
        let zone: ScreenZone
    }
    private var zoneBoundsCache: [ZoneBounds] = []
    private var lastScreenFrame: CGRect = .zero
    
    // Repeat timer for gestures
    private var repeatTimer: Timer?
    private var currentRepeatingGesture: Gesture?
    
    // Gesture lookup for efficient matching
    private var gestureLookup: GestureLookup?
    
    // Statistics
    private var zoneEnterCount = 0
    private var gestureTriggeredCount = 0
    
    // MARK: - ActivationProvider Protocol
    
    var providedActivationTypes: [ActivationType] {
        return [.screenZone]
    }
    
    func getActivationState(for type: ActivationType) -> ActivationState? {
        guard type == .screenZone else { return nil }
        return ActivationState(
            type: .screenZone,
            isEngaged: lastTriggeredZone != nil,
            metadata: [
                "zone": lastTriggeredZone?.rawValue ?? "none",
                "tracking": isMouseTrackingActive
            ]
        )
    }
    
    // MARK: - Plugin-Declared Behavioral Properties
    
    func efficiencyScore(for type: ActivationType) -> Int {
        guard type == .screenZone else { return 50 }
        return 20  // Requires active mouse tracking — expensive
    }
    
    func isAlwaysActive(for type: ActivationType) -> Bool {
        return false // Gated by higher-efficiency types (modifiers, mouse button)
    }
    
    func isInfrastructure(for type: ActivationType) -> Bool {
        return false
    }
    
    /// A gesture uses screen zone detection when it has gesture-type activation.
    func gestureUsesActivation(_ gesture: Gesture, for type: ActivationType) -> Bool {
        guard type == .screenZone else { return false }
        return gesture.activation.hasGesture
    }
    
    func enableDetection(for type: ActivationType) {
        guard type == .screenZone else { return }
        enableMouseTracking()
    }
    
    func disableDetection(for type: ActivationType) {
        guard type == .screenZone else { return }
        disableMouseTracking()
    }
    
    func isDetectionActive(for type: ActivationType) -> Bool {
        guard type == .screenZone else { return false }
        return isMouseTrackingActive
    }
    
    // MARK: - Plugin Lifecycle
    
    override func initialize(context: DetectionContext) throws {
        try super.initialize(context: context)
        
        gestureLookup = GestureLookup()
        
        ActivationCoordinator.shared.registerProvider(self, for: providedActivationTypes)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        rebuildZoneBoundsCache()
    }
    
    override func start() throws {
        try super.start()
        syncSettingsToConfiguration()
        
        // Monitors managed by ActivationCoordinator via enableDetection/disableDetection
        ActivationCoordinator.shared.rebuildDependencies()
        
        context?.logger.log("Screen zone detector started (monitors activate via efficiency system)", file: #file, function: #function, line: #line)
    }
    
    override func stop() {
        ActivationCoordinator.shared.pluginStopping(self)
        disableMouseTracking()
        stopRepeatTimer()
        lastTriggeredZone = nil
        lastTriggeredDrag = .none
        lastTriggeredModifiers = []
        lastActionTime = nil
        zoneBoundsCache.removeAll()
        super.stop()
    }
    
    override func cleanup() {
        NotificationCenter.default.removeObserver(self)
        ActivationCoordinator.shared.unregisterProvider(self)
        gestureLookup?.clear()
        gestureLookup = nil
        super.cleanup()
    }
    
    // MARK: - Mouse Tracking Control
    
    /// Enable mouse tracking (called by ActivationCoordinator).
    /// Listens to both mouseMoved and mouseDragged events — macOS stops sending
    /// mouseMoved during drags, so we need both for complete position coverage.
    /// The drag events are used purely for mouse position; button hold state
    /// is tracked by MouseButtonDetectorPlugin.
    private func enableMouseTracking() {
        guard !isMouseTrackingActive else { return }
        
        // mouseMoved — normal mouse movement
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            self?.handleMousePosition(e)
        }
        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            self?.handleMousePosition(e); return e
        }
        
        // mouseDragged — mouse movement while button held
        // We listen to all drag types for position data only
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] e in
            self?.handleMousePosition(e)
        }
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] e in
            self?.handleMousePosition(e); return e
        }
        
        isMouseTrackingActive = true
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Zone mouse tracking ENABLED", file: #file, function: #function, line: #line)
        }
        
        // Immediately check current mouse position
        checkCurrentMousePosition()
    }
    
    /// Disable mouse tracking (called by ActivationCoordinator)
    private func disableMouseTracking() {
        guard isMouseTrackingActive else { return }
        
        let monitors: [Any?] = [globalMoveMonitor, localMoveMonitor, globalDragMonitor, localDragMonitor]
        for m in monitors { if let m = m { NSEvent.removeMonitor(m) } }
        globalMoveMonitor = nil; localMoveMonitor = nil
        globalDragMonitor = nil; localDragMonitor = nil
        
        isMouseTrackingActive = false
        lastTriggeredZone = nil
        stopRepeatTimer()
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Zone mouse tracking DISABLED", file: #file, function: #function, line: #line)
        }
    }
    
    /// Check if mouse is currently in a zone and trigger gesture if so
    private func checkCurrentMousePosition() {
        let mouseLocation = NSEvent.mouseLocation
        if let zone = detectZoneFromCache(point: mouseLocation) {
            if context?.logger.isDebugEnabled ?? false {
                context?.logger.log("Mouse already in zone \(zone.rawValue) when tracking enabled", file: #file, function: #function, line: #line)
            }
            processZoneEntry(zone)
        }
    }
    
    // MARK: - Event Handler
    
    /// Unified handler for all mouse position events (moved + dragged).
    /// Only cares about position — button state comes from the coordinator.
    private func handleMousePosition(_ event: NSEvent) {
        // Throttle
        let now = Date()
        guard now.timeIntervalSince(lastProcessedMouseTime) >= mouseProcessingInterval else { return }
        lastProcessedMouseTime = now
        
        let mouseLocation = NSEvent.mouseLocation
        
        if let zone = detectZoneFromCache(point: mouseLocation) {
            processZoneEntry(zone)
        } else {
            processZoneExit()
        }
    }
    
    // MARK: - Zone Processing
    
    private func processZoneEntry(_ zone: ScreenZone) {
        let currentModifiers = NSEvent.ModifierFlags.currentSystem
        let currentDrag = currentHeldDragModifier()
        
        // Check if trigger combination changed
        let isNewTrigger = lastTriggeredZone != zone ||
                           lastTriggeredDrag != currentDrag ||
                           lastTriggeredModifiers != currentModifiers
        
        if isNewTrigger {
            stopRepeatTimer()
            
            lastTriggeredZone = zone
            lastTriggeredDrag = currentDrag
            lastTriggeredModifiers = currentModifiers
            zoneEnterCount += 1
            
            if context?.logger.isDebugEnabled ?? false {
                context?.logger.log("Detected zone: \(zone.rawValue) drag: \(currentDrag.rawValue)", file: #file, function: #function, line: #line)
            }
            
            detectGesture(zone: zone, dragModifier: currentDrag)
        }
    }
    
    private func processZoneExit() {
        if lastTriggeredZone != nil {
            lastTriggeredZone = nil
            stopRepeatTimer()
            
            if context?.logger.isDebugEnabled ?? false {
                context?.logger.log("Left all zones", file: #file, function: #function, line: #line)
            }
        }
    }
    
    private func detectGesture(zone: ScreenZone, dragModifier: DragModifier) {
        let modifiers = NSEvent.ModifierFlags.currentSystem
        
        if isInCooldownPeriod { return }
        
        guard let lookup = gestureLookup else { return }
        let matchingGestures = lookup.findMatchingGestures(
            zone: zone,
            dragModifier: dragModifier,
            modifiers: modifiers
        )
        
        if let gesture = matchingGestures.first {
            gestureTriggeredCount += 1
            
            let gestureContext = GestureContext(
                source: .screenZone(zone: zone, dragState: dragModifier),
                modifiers: modifiers,
                timestamp: Date()
            )
            
            triggerGesture(gesture, context: gestureContext)
            markActionExecuted()
            
            if gesture.repeatOnHold && gesture.repeatInterval > 0 {
                context?.logger.log("Starting repeat timer for gesture (interval=\(gesture.repeatInterval)s)", file: #file, function: #function, line: #line)
                startRepeatTimer(for: gesture)
            }
        }
    }
    
    // MARK: - Coordinator Queries
    
    /// Get the current drag modifier from the coordinator's mouseButton state.
    /// This is the single source of truth for which button is held.
    private func currentHeldDragModifier() -> DragModifier {
        let state = ActivationCoordinator.shared.getState(for: .mouseButton)
        guard state.isEngaged,
              let raw = state.metadata["heldDragModifier"] as? String,
              let drag = DragModifier(rawValue: raw) else {
            return .none
        }
        return drag
    }
    
    // MARK: - Cooldown Management
    
    private func markActionExecuted() {
        lastActionTime = Date()
    }
    
    private var isInCooldownPeriod: Bool {
        guard cooldownEnabled else { return false }
        guard let lastTime = lastActionTime else { return false }
        return Date().timeIntervalSince(lastTime) < cooldownPeriod
    }
    
    // MARK: - Repeat Timer
    
    private func startRepeatTimer(for gesture: Gesture) {
        guard gesture.repeatOnHold else { return }
        
        stopRepeatTimer()
        currentRepeatingGesture = gesture
        
        if gesture.repeatInitialDelay > 0 {
            Timer.scheduledTimer(withTimeInterval: gesture.repeatInitialDelay, repeats: false) { [weak self] _ in
                guard let self = self,
                      let g = self.currentRepeatingGesture,
                      self.shouldContinueRepeating() else { return }
                
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: g.repeatInterval, repeats: true) { [weak self] timer in
                    guard let self = self,
                          let g = self.currentRepeatingGesture,
                          self.shouldContinueRepeating() else {
                        timer.invalidate()
                        return
                    }
                    self.repeatGesture(g)
                }
                self.repeatTimer?.fire()
            }
        } else {
            repeatTimer = Timer.scheduledTimer(withTimeInterval: gesture.repeatInterval, repeats: true) { [weak self] timer in
                guard let self = self,
                      let g = self.currentRepeatingGesture,
                      self.shouldContinueRepeating() else {
                    timer.invalidate()
                    return
                }
                self.repeatGesture(g)
            }
        }
    }
    
    private func stopRepeatTimer() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        currentRepeatingGesture = nil
    }
    
    private func repeatGesture(_ gesture: Gesture) {
        let gestureContext = GestureContext(
            source: .`repeat`,
            modifiers: NSEvent.ModifierFlags.currentSystem,
            timestamp: Date()
        )
        triggerGesture(gesture, context: gestureContext)
    }
    
    /// Check if the conditions for the repeating gesture are still held.
    /// Queries system modifiers and coordinator button state — no cross-plugin access.
    private func shouldContinueRepeating() -> Bool {
        guard let gesture = currentRepeatingGesture else { return false }
        
        let currentModifiers = NSEvent.ModifierFlags.currentSystem
        let currentDrag = currentHeldDragModifier()
        
        // Check drag requirement
        if gesture.dragModifier != .none {
            guard currentDrag == gesture.dragModifier else { return false }
        }
        
        // Check modifier requirement
        let requiredModifiers = gesture.modifiers
        if requiredModifiers.isEmpty {
            // No specific modifiers required — continue if dragging or any modifier held
            if gesture.dragModifier != .none {
                return true // Drag check already passed above
            }
            return !currentModifiers.isEmpty
        }
        
        return currentModifiers.contains(requiredModifiers)
    }
    
    // MARK: - Settings Sync
    
    private func syncSettingsToConfiguration() {
        Configuration.shared.edgeThreshold = edgeThreshold
        Configuration.shared.cornerSize = cornerSize
        Configuration.shared.cornerBuffer = cornerBuffer
        
        let highlightsEnabled = settings.getBool(SettingKeys.showZoneHighlights, default: false)
        Configuration.shared.showZoneHighlights = highlightsEnabled
        Configuration.shared.showZoneLabels = settings.getBool(SettingKeys.showZoneLabels, default: false)
        Configuration.shared.zoneHighlightColor = settings.getColor(SettingKeys.zoneHighlightColor, default: NSColor.systemBlue.withAlphaComponent(0.3))
        Configuration.shared.save()
        
        if highlightsEnabled {
            ZoneHighlightManager.shared.startHighlighting()
        } else {
            ZoneHighlightManager.shared.stopHighlighting()
        }
    }
    
    // MARK: - Zone Detection
    
    private func detectZoneFromCache(point: CGPoint) -> ScreenZone? {
        if let screen = NSScreen.main, screen.frame != lastScreenFrame {
            rebuildZoneBoundsCache()
        }
        
        for zoneBound in zoneBoundsCache {
            if zoneBound.rect.contains(point) {
                return zoneBound.zone
            }
        }
        return nil
    }
    
    @objc private func screenConfigurationChanged() {
        context?.logger.log("Screen configuration changed - rebuilding zone cache", file: #file, function: #function, line: #line)
        rebuildZoneBoundsCache()
    }
    
    private func rebuildZoneBoundsCache() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        
        if screenFrame == lastScreenFrame && !zoneBoundsCache.isEmpty { return }
        
        lastScreenFrame = screenFrame
        zoneBoundsCache.removeAll()
        
        let threshold = edgeThreshold
        let cSize = cornerSize
        let cBuffer = cornerBuffer
        
        for zone in ScreenZone.allCases {
            if let bounds = calculateZoneBounds(zone: zone, screenFrame: screenFrame,
                                                threshold: threshold, cornerSize: cSize, cornerBuffer: cBuffer) {
                zoneBoundsCache.append(ZoneBounds(rect: bounds, zone: zone))
            }
        }
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Rebuilt zone bounds cache with \(zoneBoundsCache.count) zones", file: #file, function: #function, line: #line)
        }
    }
    
    private func calculateZoneBounds(zone: ScreenZone, screenFrame: CGRect, threshold: CGFloat, cornerSize: CGFloat, cornerBuffer: CGFloat) -> CGRect? {
        switch zone {
        case .topLeft:
            return CGRect(x: screenFrame.minX, y: screenFrame.maxY - cornerSize,
                         width: cornerSize + 1, height: cornerSize + 1)
        case .topRight:
            return CGRect(x: screenFrame.maxX - cornerSize, y: screenFrame.maxY - cornerSize,
                         width: cornerSize + 1, height: cornerSize + 1)
        case .bottomLeft:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY,
                         width: cornerSize + 1, height: cornerSize + 1)
        case .bottomRight:
            return CGRect(x: screenFrame.maxX - cornerSize, y: screenFrame.minY,
                         width: cornerSize + 1, height: cornerSize + 1)
        case .top:
            return CGRect(x: screenFrame.minX + cornerSize + cornerBuffer,
                         y: screenFrame.maxY - threshold,
                         width: screenFrame.width - 2 * (cornerSize + cornerBuffer) + 1,
                         height: threshold + 1)
        case .bottom:
            return CGRect(x: screenFrame.minX + cornerSize + cornerBuffer,
                         y: screenFrame.minY,
                         width: screenFrame.width - 2 * (cornerSize + cornerBuffer) + 1,
                         height: threshold + 1)
        case .left:
            return CGRect(x: screenFrame.minX,
                         y: screenFrame.minY + cornerSize + cornerBuffer,
                         width: threshold,
                         height: screenFrame.height - 2 * (cornerSize + cornerBuffer) + 1)
        case .right:
            return CGRect(x: screenFrame.maxX - threshold,
                         y: screenFrame.minY + cornerSize + cornerBuffer,
                         width: threshold,
                         height: screenFrame.height - 2 * (cornerSize + cornerBuffer) + 1)
        }
    }
    
    // MARK: - Configuration
    
    override func configurationChanged() {
        super.configurationChanged()
        rebuildZoneBoundsCache()
        gestureLookup?.rebuild()
        ActivationCoordinator.shared.rebuildDependencies()
    }
    
    override func settingChanged(_ key: String, value: Any, oldValue: Any?) {
        super.settingChanged(key, value: value, oldValue: oldValue)
        
        switch key {
        case SettingKeys.edgeThreshold:
            lastScreenFrame = .zero
            rebuildZoneBoundsCache()
            if let v = value as? Double { Configuration.shared.edgeThreshold = CGFloat(v) }
            else if let v = value as? CGFloat { Configuration.shared.edgeThreshold = v }
            Configuration.shared.save()
            NotificationCenter.default.post(name: Notification.Name("zoneDimensionsChanged"), object: nil)
            context?.logger.log("Zone bounds rebuilt due to setting change: \(key)", file: #file, function: #function, line: #line)
            
        case SettingKeys.cornerSize:
            lastScreenFrame = .zero
            rebuildZoneBoundsCache()
            if let v = value as? Double { Configuration.shared.cornerSize = CGFloat(v) }
            else if let v = value as? CGFloat { Configuration.shared.cornerSize = v }
            Configuration.shared.save()
            NotificationCenter.default.post(name: Notification.Name("zoneDimensionsChanged"), object: nil)
            context?.logger.log("Zone bounds rebuilt due to setting change: \(key)", file: #file, function: #function, line: #line)
            
        case SettingKeys.cornerBuffer:
            lastScreenFrame = .zero
            rebuildZoneBoundsCache()
            if let v = value as? Double { Configuration.shared.cornerBuffer = CGFloat(v) }
            else if let v = value as? CGFloat { Configuration.shared.cornerBuffer = v }
            Configuration.shared.save()
            NotificationCenter.default.post(name: Notification.Name("zoneDimensionsChanged"), object: nil)
            context?.logger.log("Zone bounds rebuilt due to setting change: \(key)", file: #file, function: #function, line: #line)
            
        case SettingKeys.showZoneHighlights:
            if let show = value as? Bool {
                Configuration.shared.showZoneHighlights = show
                Configuration.shared.save()
                if show { ZoneHighlightManager.shared.startHighlighting() }
                else { ZoneHighlightManager.shared.stopHighlighting() }
            }
            
        case SettingKeys.showZoneLabels:
            if let show = value as? Bool {
                Configuration.shared.showZoneLabels = show
                Configuration.shared.save()
            }
            
        case SettingKeys.zoneHighlightColor:
            if let color = value as? NSColor {
                Configuration.shared.zoneHighlightColor = color
                NotificationCenter.default.post(name: Notification.Name("zoneDimensionsChanged"), object: nil)
            }
            
        default:
            break
        }
    }
    
    // MARK: - Statistics
    
    override func getStatistics() -> DetectionPluginStatistics {
        return DetectionPluginStatistics(
            eventsDetected: zoneEnterCount,
            gesturesTriggered: gestureTriggeredCount,
            errorsEncountered: 0,
            timeSinceLastEvent: lastProcessedMouseTime.timeIntervalSinceNow * -1,
            cpuUsage: isMouseTrackingActive ? 1.0 : 0.0,
            memoryUsage: 0,
            customStats: [
                "mouseTrackingActive": isMouseTrackingActive,
                "currentZone": lastTriggeredZone?.rawValue ?? "none",
                "heldDrag": currentHeldDragModifier().rawValue,
                "zoneCacheSize": zoneBoundsCache.count,
                "inCooldown": isInCooldownPeriod
            ]
        )
    }
}
