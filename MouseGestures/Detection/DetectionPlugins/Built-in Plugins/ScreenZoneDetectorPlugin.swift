import Cocoa

// MARK: - Screen Zone Detector Plugin

/// Plugin that detects mouse movement in screen zones
class ScreenZoneDetectorPlugin: BaseDetectionPlugin {
    
    // MARK: - Constants
    
    public static let pluginIdentifier = "com.mousegestures.detection.screenzone"
    
    // MARK: - Properties
    
    override var identifier: String { Self.pluginIdentifier }
    override var name: String { "Screen Zone Detector" }
    override var description: String { "Detects mouse movement in screen edge and corner zones" }
    override var priority: Int { 150 } // Medium-high priority
    
    // Event monitors
    private var mouseMonitor: Any?
    private var dragMonitor: Any?
    private var dragEndMonitor: Any?
    
    // State tracking
    private var isMouseTrackingActive = false
    private(set) var dragState: DragModifier = .none
    private var lastTriggeredZone: ScreenZone?
    private var lastDragModifier: DragModifier = .none
    
    // Performance optimizations
    private var lastProcessedMouseTime = Date()
    private let mouseProcessingInterval: TimeInterval = 0.016 // 60 FPS max
    
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
    
    // MARK: - Plugin Lifecycle
    
    override func initialize(context: DetectionContext) throws {
        try super.initialize(context: context)
        
        // Initialize gesture lookup
        gestureLookup = GestureLookup()
        
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
        
        // Monitor drag events (left, right, and other buttons)
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            self?.handleMouseDrag(event)
        }
        
        // Monitor mouse button release to reset drag state
        dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] event in
            self?.handleMouseUp(event)
        }
        
        // DO NOT monitor mouse movement initially - will be enabled when modifiers are pressed
        mouseMonitor = nil
        isMouseTrackingActive = false
        
        context?.logger.log("Screen zone detection started (mouse tracking will activate on demand)", file: #file, function: #function, line: #line)
    }
    
    override func stop() {
        disableMouseTracking()
        
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
        
        if let monitor = dragEndMonitor {
            NSEvent.removeMonitor(monitor)
            dragEndMonitor = nil
        }
        
        stopRepeatTimer()
        dragState = .none
        lastTriggeredZone = nil
        lastDragModifier = .none
        zoneBoundsCache.removeAll()
        
        super.stop()
    }
    
    override func cleanup() {
        NotificationCenter.default.removeObserver(self)
        gestureLookup?.clear()
        gestureLookup = nil
        super.cleanup()
    }
    
    // MARK: - Mouse Tracking Control
    
    /// Enable mouse tracking when modifiers are pressed
    func enableMouseTracking() {
        guard !isMouseTrackingActive else { return }
        
        // Add mouse movement monitor
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMove(event)
        }
        
        isMouseTrackingActive = true
        
        if context?.logger.isDebugEnabled ?? false {
            if context?.logger.isDebugEnabled == true {
                context?.logger.log("Zone mouse tracking ENABLED", file: #file, function: #function, line: #line)
            }
        }
    }
    
    /// Disable mouse tracking when modifiers are released
    func disableMouseTracking() {
        guard isMouseTrackingActive else { return }
        
        // Remove mouse movement monitor
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        
        isMouseTrackingActive = false
        lastTriggeredZone = nil
        
        if context?.logger.isDebugEnabled ?? false {
            if context?.logger.isDebugEnabled == true {
                context?.logger.log("Zone mouse tracking DISABLED", file: #file, function: #function, line: #line)
            }
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleMouseMove(_ event: NSEvent) {
        // Performance: Throttle mouse movement processing to 60 FPS
        let now = Date()
        guard now.timeIntervalSince(lastProcessedMouseTime) >= mouseProcessingInterval else {
            return
        }
        lastProcessedMouseTime = now
        
        // Check if we should continue tracking
        guard shouldContinueTracking() else {
            lastTriggeredZone = nil
            stopRepeatTimer()
            disableMouseTracking()
            return
        }
        
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
        
        // Enable mouse tracking during drag (if not already enabled)
        if !isMouseTrackingActive {
            enableMouseTracking()
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
            
            // Notify that drag ended
            if !hasModifiers() {
                disableMouseTracking()
            }
        }
    }
    
    // MARK: - Zone Processing
    
    private func processZoneEntry(_ zone: ScreenZone) {
        // Check if we're still in the same zone with the same modifiers
        let isNewTrigger = lastTriggeredZone != zone || lastDragModifier != dragState
        
        if isNewTrigger {
            // Stop any existing repeat timer before starting a new gesture
            stopRepeatTimer()
            
            lastTriggeredZone = zone
            lastDragModifier = dragState
            zoneEnterCount += 1
            
            if context?.logger.isDebugEnabled ?? false {
                if context?.logger.isDebugEnabled == true {
                    context?.logger.log("Detected zone: \(zone.rawValue) with drag: \(dragState.rawValue)", file: #file, function: #function, line: #line)
                }
            }
            
            // Check for matching gestures
            detectGesture(zone: zone, dragState: dragState)
        }
        // If we're still in the same zone, don't retrigger but keep any active repeat timer running
    }
    
    private func processZoneExit() {
        // Mouse left all zones
        if lastTriggeredZone != nil {
            lastTriggeredZone = nil
            stopRepeatTimer()
            
            if context?.logger.isDebugEnabled ?? false {
                if context?.logger.isDebugEnabled == true {
                    context?.logger.log("Left all zones", file: #file, function: #function, line: #line)
                }
            }
        }
    }
    
    private func detectGesture(zone: ScreenZone, dragState: DragModifier) {
        // Get current modifiers
        let modifiers = getCurrentModifiers()
        
        // Check if in cooldown period
        if isInCooldownPeriod() {
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
            
            // Mark action executed for cooldown
            markActionExecuted()
            
            // Start repeat timer if needed
            if gesture.repeatOnHold && gesture.repeatInterval > 0 {
                context?.logger.log("Starting repeat timer for gesture (interval=\(gesture.repeatInterval)s)", file: #file, function: #function, line: #line)
                startRepeatTimer(for: gesture)
            }
        }
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
            modifiers: getCurrentModifiers(),
            timestamp: Date()
        )
        
        triggerGesture(gesture, context: gestureContext)
    }
    
    // MARK: - Helper Methods
    
    private func shouldContinueTracking() -> Bool {
        // Continue tracking if modifiers are pressed or dragging
        let realTimeModifiers = ModifierKeyDetectorPlugin.currentSystemModifiers()
        return !realTimeModifiers.isEmpty || dragState != .none
    }
    
    private func shouldContinueRepeating() -> Bool {
        guard let gesture = currentRepeatingGesture else { return false }
        
        // Get real-time system modifier state
        let currentSystemModifiers = ModifierKeyDetectorPlugin.currentSystemModifiers()
        
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
    
    private func hasModifiers() -> Bool {
        // Use real-time system modifier check instead of potentially stale plugin state
        let currentSystemModifiers = ModifierKeyDetectorPlugin.currentSystemModifiers()
        return !currentSystemModifiers.isEmpty
    }
    
    private func getCurrentModifiers() -> NSEvent.ModifierFlags {
        return context?.pluginManager?.getCurrentModifiers() ?? []
    }
    
    private func isInCooldownPeriod() -> Bool {
        guard let modifierPlugin = context?.pluginManager?.getPlugin(ModifierKeyDetectorPlugin.pluginIdentifier) as? ModifierKeyDetectorPlugin else {
            return false
        }
        return modifierPlugin.isInCooldownPeriod
    }
    
    private func markActionExecuted() {
        guard let modifierPlugin = context?.pluginManager?.getPlugin(ModifierKeyDetectorPlugin.pluginIdentifier) as? ModifierKeyDetectorPlugin else {
            return
        }
        modifierPlugin.markActionExecuted()
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
        
        guard let config = context?.configuration else { return }
        
        let threshold = config.edgeThreshold
        let cornerSize = config.cornerSize
        let cornerBuffer = config.cornerBuffer
        
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
            if context?.logger.isDebugEnabled == true {
                context?.logger.log("Rebuilt zone bounds cache with \(zoneBoundsCache.count) zones", file: #file, function: #function, line: #line)
            }
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
                "zoneCacheSize": zoneBoundsCache.count
            ]
        )
    }
}
