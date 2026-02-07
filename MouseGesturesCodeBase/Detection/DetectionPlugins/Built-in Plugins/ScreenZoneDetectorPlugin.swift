import Cocoa

// MARK: - Screen Zone Detector Plugin
/// Plugin that detects mouse movement in screen zones
/// Implements ActivationProvider for efficiency-based gating
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
    override var dependencies: [String] { [ModifierKeyDetectorPlugin.pluginIdentifier] }
    
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
    
    // Event monitors
    private var mouseMonitor: Any?
    private var dragMonitor: Any?
    private var dragEndMonitor: Any?
    private var localDragMonitor: Any?
    private var localDragEndMonitor: Any?
    private var localMouseMonitor: Any?
    
    // State tracking
    private var isMouseTrackingActive = false
    private(set) var dragState: DragModifier = .none
    private var lastTriggeredZone: ScreenZone?
    private var lastDragModifier: DragModifier = .none
    private var lastTriggeredModifiers: NSEvent.ModifierFlags = []
    
    // Cooldown tracking (owned by this plugin, not cross-plugin)
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
        return [.screenZone, .mouseDrag]
    }
    
    func getActivationState(for type: ActivationType) -> ActivationState? {
        switch type {
        case .screenZone:
            return ActivationState(
                type: .screenZone,
                isEngaged: lastTriggeredZone != nil,
                metadata: [
                    "zone": lastTriggeredZone?.rawValue ?? "none",
                    "tracking": isMouseTrackingActive
                ]
            )
        case .mouseDrag:
            return ActivationState(
                type: .mouseDrag,
                isEngaged: dragState != .none,
                metadata: ["dragState": dragState.rawValue]
            )
        default:
            return nil
        }
    }
    
    // MARK: - Plugin-Declared Behavioral Properties
    
    func efficiencyScore(for type: ActivationType) -> Int {
        switch type {
        case .screenZone: return 20  // Requires active mouse tracking
        case .mouseDrag: return 85   // Event monitoring, some state
        default: return 50
        }
    }
    
    func isAlwaysActive(for type: ActivationType) -> Bool {
        switch type {
        case .screenZone: return false // Gated by higher-efficiency types
        case .mouseDrag: return true   // Event-based, efficient
        default: return false
        }
    }
    
    func isInfrastructure(for type: ActivationType) -> Bool {
        return false
    }
    
    /// Determines whether a gesture uses screen zone or drag detection.
    /// Uses the same logic as GestureLookup.shouldIncludeGesture, unifying
    /// the activation map with the gesture detection map.
    func gestureUsesActivation(_ gesture: Gesture, for type: ActivationType) -> Bool {
        switch type {
        case .screenZone:
            return gesture.activation.hasGesture
        case .mouseDrag:
            return gesture.activation.hasGesture && gesture.dragModifier != .none
        default:
            return false
        }
    }
    
    func enableDetection(for type: ActivationType) {
        switch type {
        case .screenZone:
            enableMouseTracking()
        case .mouseDrag:
            enableDragDetection()
        default:
            break
        }
    }
    
    func disableDetection(for type: ActivationType) {
        switch type {
        case .screenZone:
            disableMouseTracking()
        case .mouseDrag:
            disableDragDetection()
        default:
            break
        }
    }
    
    func isDetectionActive(for type: ActivationType) -> Bool {
        switch type {
        case .screenZone:
            return isMouseTrackingActive
        case .mouseDrag:
            return dragMonitor != nil
        default:
            return false
        }
    }
    
    // MARK: - Plugin Lifecycle
    
    override func initialize(context: DetectionContext) throws {
        try super.initialize(context: context)
        
        // Initialize gesture lookup
        gestureLookup = GestureLookup()
        
        // Register with ActivationCoordinator
        ActivationCoordinator.shared.registerProvider(self, for: providedActivationTypes)
        
        // Listen for screen configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        // Build initial zone cache
        rebuildZoneBoundsCache()
    }
    
    override func start() throws {
        try super.start()
        
        // Sync plugin settings to Configuration
        syncSettingsToConfiguration()
        
        // All monitors managed by enableDetection/disableDetection via ActivationCoordinator
        ActivationCoordinator.shared.rebuildDependencies()
        
        context?.logger.log("Screen zone detector started (monitors activate via efficiency system)", file: #file, function: #function, line: #line)
    }
    
    
    override func stop() {
        // Notify coordinator that this plugin is stopping
        // The coordinator will clean up enabled types and engaged states
        ActivationCoordinator.shared.pluginStopping(self)
        
        // Clean up monitors directly (plugin is fully stopping)
        disableMouseTracking()
        disableDragDetection()
        stopRepeatTimer()
        dragState = .none
        lastTriggeredZone = nil
        lastDragModifier = .none
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
    
    /// Enable mouse tracking (called by ActivationCoordinator)
    func enableMouseTracking() {
        guard !isMouseTrackingActive else { return }
        
        // Add mouse movement monitor - both global and local for reliability
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMove(event)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMove(event)
            return event
        }
        
        isMouseTrackingActive = true
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Zone mouse tracking ENABLED", file: #file, function: #function, line: #line)
        }
        
        // Immediately check current mouse position
        checkCurrentMousePosition()
    }
    
    /// Check if mouse is currently in a zone and trigger gesture if so
    private func checkCurrentMousePosition() {
        let mouseLocation = NSEvent.mouseLocation
        
        // Use cached zone detection
        if let zone = detectZoneFromCache(point: mouseLocation) {
            if context?.logger.isDebugEnabled ?? false {
                context?.logger.log("Mouse already in zone \(zone.rawValue) when tracking enabled", file: #file, function: #function, line: #line)
            }
            processZoneEntry(zone)
        }
    }
    
    /// Disable mouse tracking (called by ActivationCoordinator)
    func disableMouseTracking() {
        guard isMouseTrackingActive else { return }
        
        // Remove mouse movement monitors
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        
        isMouseTrackingActive = false
        lastTriggeredZone = nil
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Zone mouse tracking DISABLED", file: #file, function: #function, line: #line)
        }
    }
    
    /// Enable drag detection (called by ActivationCoordinator)
    func enableDragDetection() {
        guard dragMonitor == nil else { return }
        
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            self?.handleMouseDrag(event)
        }
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            self?.handleMouseDrag(event)
            return event
        }
        
        dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] event in
            self?.handleMouseUp(event)
        }
        localDragEndMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] event in
            self?.handleMouseUp(event)
            return event
        }
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Drag detection ENABLED", file: #file, function: #function, line: #line)
        }
    }
    
    /// Disable drag detection (called by ActivationCoordinator)
    func disableDragDetection() {
        guard dragMonitor != nil else { return }
        
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
        if let monitor = localDragMonitor {
            NSEvent.removeMonitor(monitor)
            localDragMonitor = nil
        }
        if let monitor = dragEndMonitor {
            NSEvent.removeMonitor(monitor)
            dragEndMonitor = nil
        }
        if let monitor = localDragEndMonitor {
            NSEvent.removeMonitor(monitor)
            localDragEndMonitor = nil
        }
        
        if dragState != .none {
            dragState = .none
            ActivationCoordinator.shared.activationDisengaged(.mouseDrag)
        }
        
        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Drag detection DISABLED", file: #file, function: #function, line: #line)
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleMouseMove(_ event: NSEvent) {
        // Performance: Throttle mouse movement processing
        let now = Date()
        guard now.timeIntervalSince(lastProcessedMouseTime) >= mouseProcessingInterval else {
            return
        }
        lastProcessedMouseTime = now
        
        // Trust the ActivationCoordinator to manage when mouse tracking is active.
        // If we're here, the coordinator has enabled mouse tracking, so process the event.
        
        let mouseLocation = NSEvent.mouseLocation
        
        // Use cached zone detection for better performance
        let detectedZone = detectZoneFromCache(point: mouseLocation)
        
        if let zone = detectedZone {
            processZoneEntry(zone)
        } else {
            processZoneExit()
        }
    }
    
    private func handleMouseDrag(_ event: NSEvent) {
        // Determine which button is being dragged
        let previousDragState = dragState
        
        switch event.type {
        case .leftMouseDragged:
            dragState = .leftDrag
        case .rightMouseDragged:
            dragState = .rightDrag
        case .otherMouseDragged:
            dragState = .middleDrag
        default:
            break
        }
        
        // Notify coordinator if drag state changed
        if previousDragState == .none && dragState != .none {
            ActivationCoordinator.shared.activationEngaged(.mouseDrag, metadata: [
                "dragState": dragState.rawValue
            ])
        }
        
        // Only process zones if mouse tracking is active
        // This prevents drag zone processing when the coordinator hasn't enabled screen zones
        guard isMouseTrackingActive else {
            return
        }
        
        // Handle the mouse movement during drag
        handleMouseMove(event)
    }
    
    private func handleMouseUp(_ event: NSEvent) {
        // Reset drag state when mouse button is released
        var dragEnded = false
        
        switch event.type {
        case .leftMouseUp:
            if dragState == .leftDrag {
                dragState = .none
                dragEnded = true
            }
        case .rightMouseUp:
            if dragState == .rightDrag {
                dragState = .none
                dragEnded = true
            }
        case .otherMouseUp:
            if dragState == .middleDrag {
                dragState = .none
                dragEnded = true
            }
        default:
            break
        }
        
        if dragEnded {
            lastTriggeredZone = nil
            lastDragModifier = .none
            stopRepeatTimer()
            
            // Notify coordinator that drag ended
            ActivationCoordinator.shared.activationDisengaged(.mouseDrag)
            
        }
    }
    
    // MARK: - Zone Processing
    
    private func processZoneEntry(_ zone: ScreenZone) {
        // Get current modifiers via real-time system state
        let currentModifiers = NSEvent.ModifierFlags.currentSystem
        
        // Check if we're still in the same zone with the same modifiers and drag state
        let isNewTrigger = lastTriggeredZone != zone ||
                            lastDragModifier != dragState ||
                           lastTriggeredModifiers != currentModifiers
        
        if isNewTrigger {
            // Stop any existing repeat timer before starting a new gesture
            stopRepeatTimer()
            
            lastTriggeredZone = zone
            lastDragModifier = dragState
            lastTriggeredModifiers = currentModifiers
            zoneEnterCount += 1
            
            if context?.logger.isDebugEnabled ?? false {
                context?.logger.log("Detected zone: \(zone.rawValue) with drag: \(dragState.rawValue)", file: #file, function: #function, line: #line)
            }
            
            // Check for matching gestures
            detectGesture(zone: zone, dragState: dragState)
        }
    }
    
    private func processZoneExit() {
        // Mouse left all zones
        if lastTriggeredZone != nil {
            lastTriggeredZone = nil
            stopRepeatTimer()
            
            if context?.logger.isDebugEnabled ?? false {
                context?.logger.log("Left all zones", file: #file, function: #function, line: #line)
            }
        }
    }
    
    private func detectGesture(zone: ScreenZone, dragState: DragModifier) {
        // Get current modifiers using real-time system state
        let modifiers = NSEvent.ModifierFlags.currentSystem
        
        // Check own cooldown period
        if isInCooldownPeriod {
            return
        }
        
        // Use gesture lookup for O(1) gesture matching
        guard let lookup = gestureLookup else { return }
        let matchingGestures = lookup.findMatchingGestures(
            zone: zone,
            dragModifier: dragState,
            modifiers: modifiers
        )
        
        // Execute the first matching gesture (if any)
        if let gesture = matchingGestures.first {
            gestureTriggeredCount += 1
            
            // Create gesture context
            let gestureContext = GestureContext(
                source: .screenZone(zone: zone, dragState: dragState),
                modifiers: modifiers,
                timestamp: Date()
            )
            
            // Trigger the gesture
            triggerGesture(gesture, context: gestureContext)
            
            // Mark action executed for own cooldown tracking
            markActionExecuted()
            
            // Start repeat timer if needed
            if gesture.repeatOnHold && gesture.repeatInterval > 0 {
                context?.logger.log("Starting repeat timer for gesture (interval=\(gesture.repeatInterval)s)", file: #file, function: #function, line: #line)
                startRepeatTimer(for: gesture)
            }
        }
    }
    
    // MARK: - Cooldown Management
    
    /// Mark that a gesture action was executed (for cooldown tracking)
    private func markActionExecuted() {
        lastActionTime = Date()
    }
    
    /// Check if we're in cooldown period
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
                      let repeatingGesture = self.currentRepeatingGesture,
                      self.shouldContinueRepeating() else { return }
                
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: repeatingGesture.repeatInterval, repeats: true) { [weak self] timer in
                    guard let self = self,
                          let repeatingGesture = self.currentRepeatingGesture,
                          self.shouldContinueRepeating() else {
                        timer.invalidate()
                        return
                    }
                    
                    self.repeatGesture(repeatingGesture)
                }
                
                self.repeatTimer?.fire()
            }
        } else {
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: gesture.repeatInterval, repeats: true) { [weak self] timer in
                guard let self = self,
                      let repeatingGesture = self.currentRepeatingGesture,
                      self.shouldContinueRepeating() else {
                    timer.invalidate()
                    return
                }
                
                self.repeatGesture(repeatingGesture)
            }
        }
    }
    
    private func stopRepeatTimer() {
        if let timer = repeatTimer {
            timer.invalidate()
            repeatTimer = nil
            currentRepeatingGesture = nil
        }
    }
    
    private func repeatGesture(_ gesture: Gesture) {
        let gestureContext = GestureContext(
            source: .`repeat`,
            modifiers: NSEvent.ModifierFlags.currentSystem,
            timestamp: Date()
        )
        
        triggerGesture(gesture, context: gestureContext)
    }
    
    // MARK: - Helper Methods
    
    // Modifier normalization and system query use shared
    // NSEvent.ModifierFlags extensions in Extensions.swift.
    
    private func shouldContinueRepeating() -> Bool {
        guard let gesture = currentRepeatingGesture else { return false }
        
        // Use real-time system modifiers for accuracy during repeat
        // This is a direct system query, not cross-plugin access
        let currentSystemModifiers = NSEvent.ModifierFlags.currentSystem
        
        // Check if required modifiers for the gesture are still held
        let requiredModifiers = gesture.modifiers
        
        // If gesture has no modifier requirements, check if any modifiers are held or if dragging
        if requiredModifiers.isEmpty {
            // For drag-based gestures, continue while still dragging
            if gesture.dragModifier != .none {
                return dragState == gesture.dragModifier
            }
            // For modifier-based gestures without specific modifiers, any modifier counts
            return !currentSystemModifiers.isEmpty
        }
        
        // For gestures with specific modifier requirements, check if those modifiers are still held
        let hasRequiredModifiers = currentSystemModifiers.contains(requiredModifiers)
        
        // Also check drag state if the gesture requires it
        if gesture.dragModifier != .none {
            return hasRequiredModifiers && dragState == gesture.dragModifier
        }
        
        return hasRequiredModifiers
    }
    
    // MARK: - Settings Sync
    
    /// Sync plugin settings to Configuration.shared so ZoneHighlightManager and other
    /// consumers that read from Configuration stay in sync with the actual detection values.
    private func syncSettingsToConfiguration() {
        Configuration.shared.edgeThreshold = edgeThreshold
        Configuration.shared.cornerSize = cornerSize
        Configuration.shared.cornerBuffer = cornerBuffer
        
        let highlightsEnabled = settings.getBool(SettingKeys.showZoneHighlights, default: false)
        Configuration.shared.showZoneHighlights = highlightsEnabled
        Configuration.shared.showZoneLabels = settings.getBool(SettingKeys.showZoneLabels, default: false)
        Configuration.shared.zoneHighlightColor = settings.getColor(SettingKeys.zoneHighlightColor, default: NSColor.systemBlue.withAlphaComponent(0.3))
        Configuration.shared.save()
        
        // Activate/deactivate zone highlights based on current setting
        if highlightsEnabled {
            ZoneHighlightManager.shared.startHighlighting()
        } else {
            ZoneHighlightManager.shared.stopHighlighting()
        }
    }
    
    // MARK: - Zone Detection
    
    private func detectZoneFromCache(point: CGPoint) -> ScreenZone? {
        // Check if screen configuration has changed
        if let screen = NSScreen.main, screen.frame != lastScreenFrame {
            rebuildZoneBoundsCache()
        }
        
        // Use cached bounds for fast zone detection
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
        
        // Only rebuild if screen frame has changed
        if screenFrame == lastScreenFrame && !zoneBoundsCache.isEmpty {
            return
        }
        
        lastScreenFrame = screenFrame
        zoneBoundsCache.removeAll()
        
        // Use plugin settings
        let threshold = edgeThreshold
        let cornerSize = self.cornerSize
        let cornerBuffer = self.cornerBuffer
        
        // Pre-calculate bounds for all zones
        for zone in ScreenZone.allCases {
            let bounds = calculateZoneBounds(zone: zone,
                                           screenFrame: screenFrame,
                                           threshold: threshold,
                                           cornerSize: cornerSize,
                                           cornerBuffer: cornerBuffer)
            if let bounds = bounds {
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
            return CGRect(x: screenFrame.minX,
                         y: screenFrame.maxY - cornerSize,
                         width: cornerSize + 1,
                         height: cornerSize + 1)
        case .topRight:
            return CGRect(x: screenFrame.maxX - cornerSize,
                         y: screenFrame.maxY - cornerSize,
                         width: cornerSize + 1,
                         height: cornerSize + 1)
        case .bottomLeft:
            return CGRect(x: screenFrame.minX,
                         y: screenFrame.minY,
                         width: cornerSize + 1,
                         height: cornerSize + 1)
        case .bottomRight:
            return CGRect(x: screenFrame.maxX - cornerSize,
                         y: screenFrame.minY,
                         width: cornerSize + 1,
                         height: cornerSize + 1)
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
        
        // Notify coordinator to rebuild dependencies
        ActivationCoordinator.shared.rebuildDependencies()
    }
    
    override func settingChanged(_ key: String, value: Any, oldValue: Any?) {
        super.settingChanged(key, value: value, oldValue: oldValue)
        
        // Sync all relevant settings to Configuration so ZoneHighlightManager stays current
        switch key {
        case SettingKeys.edgeThreshold:
            lastScreenFrame = .zero  // Force rebuild
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
                if show {
                    ZoneHighlightManager.shared.startHighlighting()
                } else {
                    ZoneHighlightManager.shared.stopHighlighting()
                }
            }
            
        case SettingKeys.showZoneLabels:
            if let show = value as? Bool {
                Configuration.shared.showZoneLabels = show
                Configuration.shared.save()
            }
            
        case SettingKeys.zoneHighlightColor:
            if let color = value as? NSColor {
                Configuration.shared.zoneHighlightColor = color
                // Force redraw of visible zone windows
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
                "dragState": dragState.rawValue,
                "zoneCacheSize": zoneBoundsCache.count,
                "inCooldown": isInCooldownPeriod
            ]
        )
    }
}
