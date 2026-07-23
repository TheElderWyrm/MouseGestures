import Cocoa

// MARK: - Screen Zone Detector Plugin
/// Plugin that detects mouse movement in screen zones.
/// Only responsible for mouse position → zone detection.
/// Button hold state is queried in real-time via DragModifier.currentSystem.
/// Modifier state is queried via NSEvent.ModifierFlags.currentSystem.
///
/// mouseDragged monitors are only installed when drag gestures exist,
/// avoiding unnecessary event processing during normal mouse-button holds.
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
    }

    // MARK: - Properties

    override var identifier: String { Self.pluginIdentifier }
    override var name: String { "Screen Zone Detector" }
    override var description: String { "Detects mouse movement in screen edge and corner zones" }
    override var priority: Int { 150 }
    override var dependencies: [String] { [ModifierKeyDetectorPlugin.pluginIdentifier, MouseButtonDetectorPlugin.pluginIdentifier] }
    override var triggerIcon: String { "square.grid.3x3" }
    override var triggerTitle: String { "Screen Zone" }
    override var triggerDescription: String { "Activate in a specific screen zone" }
    override var providesTriggerUI: Bool { true }

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
                key: "previewZoneHighlights",
                displayName: "Preview Zone Highlights",
                description: "Temporarily show zone highlights to preview your size settings",
                category: .detection,
                type: .button(title: "Preview Zones", style: .primary, action: { [weak self] in
                    self?.previewZoneHighlights()
                }),
                defaultValue: false,
                isAdvanced: false
            ),
            PluginSettingDefinition(
                key: SettingKeys.showZoneHighlights,
                displayName: "Show Zone Highlights",
                description: "Display visual overlay showing detection zones",
                category: .detection,
                type: .toggle(label: "Enabled"),
                defaultValue: false,
                isAdvanced: false
            ),
            PluginSettingDefinition(
                key: SettingKeys.showZoneLabels,
                displayName: "Show Zone Labels",
                description: "Display zone names when highlights are shown",
                category: .detection,
                type: .toggle(label: "Enabled"),
                defaultValue: false,
                isAdvanced: false,
                dependsOn: .init(key: SettingKeys.showZoneHighlights, condition: .isTrue)
            ),
            PluginSettingDefinition(
                key: SettingKeys.zoneHighlightColor,
                displayName: "Highlight Color",
                description: "Color used for zone highlight overlay",
                category: .detection,
                type: .color,
                defaultValue: NSColor.systemBlue.withAlphaComponent(0.3),
                isAdvanced: false,
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

    // Event monitors
    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    private var globalDragMonitor: Any?   // Only installed when drag gestures exist
    private var localDragMonitor: Any?    // Only installed when drag gestures exist

    // State tracking (zone detection only — no button/drag ownership)
    private var isMouseTrackingActive = false
    private var isDragMonitorInstalled = false
    private var hasDragGestures = false   // Cached flag, rebuilt on config change
    private var lastTriggeredZone: ScreenZone?
    private var lastTriggeredDrag: DragModifier = .none
    private var lastTriggeredModifiers: NSEvent.ModifierFlags = []

    // Cached system state to avoid repeated queries
    private var cachedDragModifier: DragModifier = .none
    private var cachedModifiers: NSEvent.ModifierFlags = []

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
    // One-shot initial-delay timer that gates the start of the repeating timer.
    // Must be tracked so it can be invalidated if the gesture ends during the
    // delay window; otherwise a rapid zone re-entry can fire the orphaned
    // delay timer and corrupt the repeat state for the new gesture.
    private var repeatInitialDelayTimer: Timer?
    private var currentRepeatingGesture: Gesture?

    // Gesture lookup for efficient matching
    private var gestureLookup: GestureLookup?

    // Keys of combined (click-or-drag) gestures fired by click detection.
    // Suppresses re-firing when zone tracking starts after a button press.
    private var clickFiredKeys: Set<String> = []

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

    // REMOVED: gestureUsesActivation - moved to ActivationMapper
    // Plugin no longer needs to understand gesture structure

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
        rebuildDragGestureFlag()
    }

    override func start() throws {
        try super.start()
        syncSettingsToConfiguration()
        ActivationCoordinator.shared.rebuildDependencies()

        context?.logger.log("Screen zone detector started (drag gestures: \(hasDragGestures))", file: #file, function: #function, line: #line)
    }

    override func stop() {
        ActivationCoordinator.shared.pluginStopping(self)
        disableMouseTracking()
        stopRepeatTimer()
        lastTriggeredZone = nil
        lastTriggeredDrag = .none
        lastTriggeredModifiers = []
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

    // MARK: - Drag Gesture Detection

    /// Rebuild the cached flag for whether any enabled gesture uses drag.
    /// Called on config change to avoid per-event gesture scanning.
    private func rebuildDragGestureFlag() {
        let gestures = context?.configuration.gestures ?? Configuration.shared.gestures
        hasDragGestures = gestures.contains { $0.isEnabled && $0.hasZoneTrigger && $0.dragModifier != .none }

        // If tracking is active, update drag monitors to match
        if isMouseTrackingActive {
            if hasDragGestures && !isDragMonitorInstalled {
                installDragMonitors()
            } else if !hasDragGestures && isDragMonitorInstalled {
                removeDragMonitors()
            }
        }
    }

    // MARK: - Mouse Tracking Control

    /// Enable mouse tracking (called by ActivationCoordinator).
    /// Always installs mouseMoved monitors.
    /// Only installs mouseDragged monitors when drag gestures are configured.
    private func enableMouseTracking() {
        guard !isMouseTrackingActive else { return }

        // mouseMoved — always needed for zone detection
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            self?.handleMousePosition(e)
        }
        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            self?.handleMousePosition(e); return e
        }

        isMouseTrackingActive = true

        // mouseDragged — only if drag gestures exist
        if hasDragGestures {
            installDragMonitors()
        }

        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Zone tracking ENABLED (drag monitors: \(hasDragGestures))", file: #file, function: #function, line: #line)
        }

        checkCurrentMousePosition()
    }

    /// Disable all mouse tracking (called by ActivationCoordinator)
    private func disableMouseTracking() {
        guard isMouseTrackingActive else { return }

        if let m = globalMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = localMoveMonitor { NSEvent.removeMonitor(m) }
        globalMoveMonitor = nil; localMoveMonitor = nil

        removeDragMonitors()

        isMouseTrackingActive = false
        lastTriggeredZone = nil
        stopRepeatTimer()

        // Clear cached state
        cachedDragModifier = .none
        cachedModifiers = []

        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Zone tracking DISABLED", file: #file, function: #function, line: #line)
        }
    }

    /// Install mouseDragged monitors (macOS stops mouseMoved during drags)
    private func installDragMonitors() {
        guard !isDragMonitorInstalled else { return }

        let dragEvents: NSEvent.EventTypeMask = [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: dragEvents) { [weak self] e in
            self?.handleMousePosition(e)
        }
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: dragEvents) { [weak self] e in
            self?.handleMousePosition(e); return e
        }

        isDragMonitorInstalled = true

        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Drag monitors INSTALLED", file: #file, function: #function, line: #line)
        }
    }

    /// Remove mouseDragged monitors
    private func removeDragMonitors() {
        guard isDragMonitorInstalled else { return }

        if let m = globalDragMonitor { NSEvent.removeMonitor(m) }
        if let m = localDragMonitor { NSEvent.removeMonitor(m) }
        globalDragMonitor = nil; localDragMonitor = nil

        isDragMonitorInstalled = false

        if context?.logger.isDebugEnabled ?? false {
            context?.logger.log("Drag monitors REMOVED", file: #file, function: #function, line: #line)
        }
    }

    /// Check if mouse is currently in a zone
    private func checkCurrentMousePosition() {
        let mouseLocation = NSEvent.mouseLocation
        // Refresh the cached drag/modifier state BEFORE zone processing.
        // handleMousePosition() is what normally populates these caches, but
        // it has not run for this enable. processZoneEntry/detectGesture read
        // the caches directly, so without this refresh a gesture that fires
        // the instant tracking engages would use stale (or default .none/[])
        // values and match the wrong gesture — e.g. a ⌘+drag-gated corner
        // gesture wouldn't fire, and a no-modifier one might fire instead.
        cachedDragModifier = DragModifier.currentSystem
        cachedModifiers = NSEvent.ModifierFlags.currentSystem
        if let zone = detectZoneFromCache(point: mouseLocation) {
            if context?.logger.isDebugEnabled ?? false {
                context?.logger.log("Mouse already in zone \(zone.rawValue) when tracking enabled", file: #file, function: #function, line: #line)
            }
            processZoneEntry(zone)
        }
    }

    // MARK: - Event Handler

    /// Unified handler for all mouse position events (moved + dragged).
    /// Caches system state to avoid repeated queries during continuous movement.
    private func handleMousePosition(_ event: NSEvent) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessedMouseTime) >= mouseProcessingInterval else { return }
        lastProcessedMouseTime = now

        let mouseLocation = NSEvent.mouseLocation

        // Update cached state on every mouse event (but only query once per event)
        cachedDragModifier = DragModifier.currentSystem
        cachedModifiers = NSEvent.ModifierFlags.currentSystem

        if let zone = detectZoneFromCache(point: mouseLocation) {
            processZoneEntry(zone)
        } else {
            processZoneExit()
        }
    }

    // MARK: - Zone Processing

    private func processZoneEntry(_ zone: ScreenZone) {
        // Use cached state from handleMousePosition (single query per mouse event)
        // Normalize modifiers to only track user-meaningful keys (⌘⌃⌥⇧),
        // preventing spurious re-triggers from transient system flags
        let currentModifiers = cachedModifiers.normalized
        let currentDrag = cachedDragModifier

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
                context?.logger.log("Zone: \(zone.rawValue) drag: \(currentDrag.rawValue) mods: \(currentModifiers.symbolString)", file: #file, function: #function, line: #line)
            }

            detectGesture(zone: zone, dragModifier: currentDrag)
        }
    }

    private func processZoneExit() {
        if lastTriggeredZone != nil {
            lastTriggeredZone = nil
            stopRepeatTimer()
        }
    }

    /// Called by MouseButtonDetectorPlugin after a combined gesture fires via click.
    /// Prevents this plugin from re-firing the same gesture when zone tracking starts.
    func suppressClickFiring(forKey key: String) {
        clickFiredKeys.insert(key)
        // Clear the suppression after a brief window — long enough to cover the
        // synchronous activationEngaged path, but short enough not to block legitimate
        // drag re-entries after the button is released and re-pressed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.clickFiredKeys.remove(key)
        }
    }

    private func detectGesture(zone: ScreenZone, dragModifier: DragModifier) {
        // Use cached modifiers, normalized to match GestureLookup key format
        let modifiers = cachedModifiers.normalized

        guard let lookup = gestureLookup else { return }
        // • Filter out pure click gestures (mouseButton enabled, dragModifier == .none)
        //   — they fire exclusively via click detection in MouseButtonDetectorPlugin.
        // • Filter out combined (click/drag) gestures that were just fired by click
        //   detection — prevents double-firing when zone tracking starts after the click.
        let matching = lookup.findMatchingGestures(zone: zone, dragModifier: dragModifier, modifiers: modifiers)
            .filter { gesture in
                if gesture.components.mouseButton?.isEnabled == true && gesture.dragModifier == .none { return false }
                if gesture.components.dragType?.allowClick == true && clickFiredKeys.contains(gesture.triggerKey) { return false }
                return true
            }

        if let gesture = matching.first {
            gestureTriggeredCount += 1

            triggerGesture(gesture, context: GestureContext(
                source: .screenZone(zone: zone, dragState: dragModifier),
                modifiers: modifiers, timestamp: Date()
            ))

            if gesture.repeatOnHold && gesture.repeatInterval > 0 {
                startRepeatTimer(for: gesture)
            }
        }
    }

    // MARK: - Repeat Timer

    private func startRepeatTimer(for gesture: Gesture) {
        guard gesture.repeatOnHold else { return }
        stopRepeatTimer()
        currentRepeatingGesture = gesture

        let startRepeating = { [weak self] in
            guard let self = self, let g = self.currentRepeatingGesture,
                  self.shouldContinueRepeating() else { return }

            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: g.repeatInterval, repeats: true) { [weak self] timer in
                guard let self = self, let g = self.currentRepeatingGesture,
                      self.shouldContinueRepeating() else { timer.invalidate(); return }
                self.repeatGesture(g)
            }
            self.repeatTimer?.fire()
        }

        if gesture.repeatInitialDelay > 0 {
            repeatInitialDelayTimer = Timer.scheduledTimer(withTimeInterval: gesture.repeatInitialDelay, repeats: false) { [weak self] _ in
                // Clear the delay timer reference once it has fired so a later
                // stopRepeatTimer() doesn't try to invalidate a dead timer.
                self?.repeatInitialDelayTimer = nil
                startRepeating()
            }
        } else {
            startRepeating()
        }
    }

    private func stopRepeatTimer() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatInitialDelayTimer?.invalidate()
        repeatInitialDelayTimer = nil
        currentRepeatingGesture = nil
    }

    private func repeatGesture(_ gesture: Gesture) {
        triggerGesture(gesture, context: GestureContext(
            source: .`repeat`,
            modifiers: NSEvent.ModifierFlags.currentSystem,
            timestamp: Date()
        ))
    }

    /// Check if conditions for the repeating gesture are still held.
    /// Queries system state once per check (timer-based, not per-event).
    private func shouldContinueRepeating() -> Bool {
        guard let gesture = currentRepeatingGesture else { return false }

        // Check gesture is still enabled
        guard gesture.isEnabled else { return false }

        // Check mouse is still in the correct zone
        let mouseLocation = NSEvent.mouseLocation
        let currentZone = detectZoneFromCache(point: mouseLocation)
        guard currentZone == gesture.zone else { return false }

        // Query system state (this is timer-based, not per-mouse-event, so overhead is acceptable)
        let mods = NSEvent.ModifierFlags.currentSystem
        let drag = DragModifier.currentSystem

        // Check "No Mouse" requirement — reject if any mouse button is held
        if gesture.components.requireNoMouse && drag != DragModifier.none { return false }

        // Check drag requirement
        if gesture.dragModifier != .none {
            if gesture.dragModifier == .anyDrag {
                guard drag != .none else { return false }
            } else {
                guard drag == gesture.dragModifier else { return false }
            }
        }

        // Check modifier requirement
        let required = gesture.modifiers
        if required.isEmpty {
            if gesture.dragModifier != .none { return true } // Drag check passed above
            // A zone-only gesture (no modifier, no drag requirement) has no
            // modifier/drag condition to keep held — the cursor staying in the
            // zone (already verified above) is the entire "hold". Repeating
            // must continue regardless of modifier state; the old `!mods.isEmpty`
            // check made repeat-on-hold silently never work for plain zone
            // gestures (it only repeated while an unrelated key happened down).
            return true
        }
        return mods.contains(required)
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

        if highlightsEnabled { ZoneHighlightManager.shared.startHighlighting() } else { ZoneHighlightManager.shared.stopHighlighting() }
    }

    // MARK: - Zone Detection

    private func detectZoneFromCache(point: CGPoint) -> ScreenZone? {
        if let screen = NSScreen.main, screen.frame != lastScreenFrame {
            rebuildZoneBoundsCache()
        }
        for zb in zoneBoundsCache {
            if zb.rect.contains(point) { return zb.zone }
        }
        return nil
    }

    @objc private func screenConfigurationChanged() {
        context?.logger.log("Screen configuration changed - rebuilding zone cache", file: #file, function: #function, line: #line)
        rebuildZoneBoundsCache()
    }

    private func rebuildZoneBoundsCache() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.frame
        if sf == lastScreenFrame && !zoneBoundsCache.isEmpty { return }

        lastScreenFrame = sf
        zoneBoundsCache.removeAll()

        let t = edgeThreshold, cs = cornerSize, cb = cornerBuffer

        for zone in ScreenZone.allCases {
            if let bounds = calculateZoneBounds(zone: zone, sf: sf, t: t, cs: cs, cb: cb) {
                zoneBoundsCache.append(ZoneBounds(rect: bounds, zone: zone))
            }
        }
    }

    private func calculateZoneBounds(zone: ScreenZone, sf: CGRect, t: CGFloat, cs: CGFloat, cb: CGFloat) -> CGRect? {
        switch zone {
        case .topLeft:     return CGRect(x: sf.minX, y: sf.maxY - cs, width: cs + 1, height: cs + 1)
        case .topRight:    return CGRect(x: sf.maxX - cs, y: sf.maxY - cs, width: cs + 1, height: cs + 1)
        case .bottomLeft:  return CGRect(x: sf.minX, y: sf.minY, width: cs + 1, height: cs + 1)
        case .bottomRight: return CGRect(x: sf.maxX - cs, y: sf.minY, width: cs + 1, height: cs + 1)
        case .top:
            return CGRect(x: sf.minX + cs + cb, y: sf.maxY - t,
                         width: sf.width - 2 * (cs + cb) + 1, height: t + 1)
        case .bottom:
            return CGRect(x: sf.minX + cs + cb, y: sf.minY,
                         width: sf.width - 2 * (cs + cb) + 1, height: t + 1)
        case .left:
            return CGRect(x: sf.minX, y: sf.minY + cs + cb,
                         width: t, height: sf.height - 2 * (cs + cb) + 1)
        case .right:
            return CGRect(x: sf.maxX - t, y: sf.minY + cs + cb,
                         width: t, height: sf.height - 2 * (cs + cb) + 1)
        }
    }

    // MARK: - Configuration

    override func configurationChanged() {
        super.configurationChanged()
        rebuildZoneBoundsCache()
        gestureLookup?.rebuild()
        rebuildDragGestureFlag()
        ActivationCoordinator.shared.rebuildDependencies()
    }

    override func settingChanged(_ key: String, value: Any, oldValue: Any?) {
        super.settingChanged(key, value: value, oldValue: oldValue)

        switch key {
        case SettingKeys.edgeThreshold:
            lastScreenFrame = .zero; rebuildZoneBoundsCache()
            if let v = value as? Double { Configuration.shared.edgeThreshold = CGFloat(v) } else if let v = value as? CGFloat { Configuration.shared.edgeThreshold = v }
            Configuration.shared.save()
            NotificationCenter.default.post(name: Notification.Name("zoneDimensionsChanged"), object: nil)

        case SettingKeys.cornerSize:
            lastScreenFrame = .zero; rebuildZoneBoundsCache()
            if let v = value as? Double { Configuration.shared.cornerSize = CGFloat(v) } else if let v = value as? CGFloat { Configuration.shared.cornerSize = v }
            Configuration.shared.save()
            NotificationCenter.default.post(name: Notification.Name("zoneDimensionsChanged"), object: nil)

        case SettingKeys.cornerBuffer:
            lastScreenFrame = .zero; rebuildZoneBoundsCache()
            if let v = value as? Double { Configuration.shared.cornerBuffer = CGFloat(v) } else if let v = value as? CGFloat { Configuration.shared.cornerBuffer = v }
            Configuration.shared.save()
            NotificationCenter.default.post(name: Notification.Name("zoneDimensionsChanged"), object: nil)

        case SettingKeys.showZoneHighlights:
            if let show = value as? Bool {
                Configuration.shared.showZoneHighlights = show; Configuration.shared.save()
                if show { ZoneHighlightManager.shared.startHighlighting() } else { ZoneHighlightManager.shared.stopHighlighting() }
            }

        case SettingKeys.showZoneLabels:
            if let v = value as? Bool { Configuration.shared.showZoneLabels = v; Configuration.shared.save() }

        case SettingKeys.zoneHighlightColor:
            if let c = value as? NSColor {
                Configuration.shared.zoneHighlightColor = c
                NotificationCenter.default.post(name: Notification.Name("zoneDimensionsChanged"), object: nil)
            }

        default: break
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
                "dragMonitorsActive": isDragMonitorInstalled,
                "hasDragGestures": hasDragGestures,
                "currentZone": lastTriggeredZone?.rawValue ?? "none",
                "zoneCacheSize": zoneBoundsCache.count
            ]
        )
    }

    // MARK: - Zone Preview

    /// Temporarily shows zone highlights for preview (called from button action)
    private func previewZoneHighlights() {
        context?.logger.log("Zone preview started", file: #file, function: #function, line: #line)

        // Show zones in preview mode for 5 seconds
        ZoneHighlightManager.shared.showPreview(duration: 5.0)
    }
}
