import Cocoa

// MARK: - Individual Zone Window (Memory Optimized)

/// A small window that highlights a single zone - much more memory efficient than a full-screen window
class ZoneWindow: NSWindow {
    let zone: ScreenZone
    private var zoneView: ZoneView?

    init(zone: ScreenZone, frame: NSRect) {
        self.zone = zone
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        setupWindow()
        setupView()
    }

    private func setupWindow() {
        isOpaque = false
        backgroundColor = NSColor.clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
    }

    private func setupView() {
        zoneView = ZoneView(frame: NSRect(origin: .zero, size: frame.size), zone: zone)
        contentView = zoneView
    }

    func updateState(isActive: Bool, label: String?, forceLabel: Bool = false) {
        zoneView?.isActive = isActive
        zoneView?.label = label
        zoneView?.forceShowLabel = forceLabel
        zoneView?.needsDisplay = true
    }

    override func close() {
        zoneView = nil
        super.close()
    }
}

/// View for a single zone
class ZoneView: NSView {
    let zone: ScreenZone
    var isActive: Bool = false
    var label: String?
    var forceShowLabel: Bool = false

    private var glowColor: NSColor {
        Configuration.shared.zoneHighlightColor
    }

    init(frame: NSRect, zone: ScreenZone) {
        self.zone = zone
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        // No flat fill: like the website demo's zone visualization, the
        // entire visual is the directional glow drawn below (corners glow
        // from the screen corner inward, edges glow from the screen edge
        // inward) — never a hard box.
        drawGlow()

        // Draw label if present (forceShowLabel bypasses the global setting for preview mode)
        if let label = label, forceShowLabel || Configuration.shared.showZoneLabels {
            // Use smaller font for narrow zones
            let isNarrow = min(bounds.width, bounds.height) < 50
            let fontSize: CGFloat = isNarrow ? 9 : 11
            let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]
            let size = label.size(withAttributes: attrs)
            let pad: CGFloat = 3

            // Rotate text for narrow vertical zones (left/right edges)
            let needsRotation = bounds.width < 50 && bounds.height > bounds.width * 2

            if needsRotation {
                // Draw rotated: use height as available width for text
                let availableW = bounds.height - pad * 2
                let labelW = min(size.width, availableW)
                let labelH = size.height

                let ctx = NSGraphicsContext.current!.cgContext
                ctx.saveGState()

                // Translate to center, rotate 90° CCW, then offset
                let cx = bounds.width / 2
                let cy = bounds.height / 2
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: .pi / 2)

                // Draw pill background
                let pillRect = NSRect(x: -labelW / 2 - 3, y: -labelH / 2 - 1, width: labelW + 6, height: labelH + 2)
                let pill = NSBezierPath(roundedRect: pillRect, xRadius: 3, yRadius: 3)
                NSColor.black.withAlphaComponent(0.5).setFill()
                pill.fill()

                // Draw text
                let drawRect = NSRect(x: -labelW / 2, y: -labelH / 2, width: labelW, height: labelH)
                label.draw(with: drawRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)

                ctx.restoreGState()
            } else {
                // Normal horizontal drawing
                let labelW = min(size.width, bounds.width - pad * 2)
                let labelH = size.height
                let x = max(pad, min((bounds.width - labelW) / 2, bounds.width - labelW - pad))
                let y = max(pad, min((bounds.height - labelH) / 2, bounds.height - labelH - pad))

                // Draw background pill for readability
                let pillRect = NSRect(x: x - 3, y: y - 1, width: labelW + 6, height: labelH + 2)
                let pill = NSBezierPath(roundedRect: pillRect, xRadius: 3, yRadius: 3)
                NSColor.black.withAlphaComponent(0.5).setFill()
                pill.fill()

                // Draw text clipped to zone
                let drawRect = NSRect(x: x, y: y, width: labelW, height: labelH)
                label.draw(with: drawRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
            }
        }
    }

    /// Soft inner glow along the zone's edge, replacing the old hard-edged
    /// box border. Drawn as a blurred stroke inset from the bounds so the
    /// shadow blur stays within the (unclipped-beyond-bounds) view.
    /// Directional glow matching the website demo's zone visualization:
    /// corner zones glow outward from the screen's actual corner (radial),
    /// edge zones glow inward from the screen's edge (linear) — brightest at
    /// the screen boundary, fading to nothing at the zone's inner edge.
    private func drawGlow() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }

        let peakAlpha: CGFloat = isActive ? 0.85 : 0.32
        let bright = glowColor.withAlphaComponent(peakAlpha).cgColor
        let clear = glowColor.withAlphaComponent(0).cgColor
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [bright, clear] as CFArray, locations: [0, 1]) else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }

        switch zone {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let corner: CGPoint
            switch zone {
            case .topLeft: corner = CGPoint(x: 0, y: bounds.height)
            case .topRight: corner = CGPoint(x: bounds.width, y: bounds.height)
            case .bottomLeft: corner = CGPoint(x: 0, y: 0)
            default: corner = CGPoint(x: bounds.width, y: 0) // .bottomRight
            }
            let radius = max(bounds.width, bounds.height) * 1.15
            ctx.drawRadialGradient(gradient, startCenter: corner, startRadius: 0, endCenter: corner, endRadius: radius, options: [])

        case .top, .bottom, .left, .right:
            let start: CGPoint
            let end: CGPoint
            switch zone {
            case .top: start = CGPoint(x: bounds.midX, y: bounds.height); end = CGPoint(x: bounds.midX, y: 0)
            case .bottom: start = CGPoint(x: bounds.midX, y: 0); end = CGPoint(x: bounds.midX, y: bounds.height)
            case .left: start = CGPoint(x: 0, y: bounds.midY); end = CGPoint(x: bounds.width, y: bounds.midY)
            default: start = CGPoint(x: bounds.width, y: bounds.midY); end = CGPoint(x: 0, y: bounds.midY) // .right
            }
            ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
        }
    }
}

// MARK: - Zone Highlight Manager (Memory Optimized)

/// Manages zone highlight windows using individual small windows per zone
class ZoneHighlightManager {
    static let shared = ZoneHighlightManager()

    private var zoneWindows: [ScreenZone: ZoneWindow] = [:]
    private var modifierMonitor: Any?
    private var hideTimer: Timer?
    private var configChangeObserver: Any?
    private var screenChangeObserver: Any?
    private var dimensionChangeObserver: Any?
    private var modifierStateObserver: Any?
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var localModifierMonitor: Any?
    private var modifierCheckTimer: Timer?
    private var appEventObservers: [Any] = []
    private var isHiding = false
    /// Monotonic generation token for hide animations. Each hideZones() call
    /// captures the current value and increments it; the animation completion
    /// only closes windows if its captured generation still matches the
    /// current one. This stops a stale completion (from an earlier, superseded
    /// hide) from closing windows out from under a newer show/hide in progress
    /// — which otherwise caused abrupt (non-animated) disappearance on rapid
    /// modifier press/release/press.
    private var hideGeneration = 0

    private init() {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GestureConfigurationChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshZoneStates()
        }

        // Listen for modifier state changes from ModifierKeyDetectorPlugin
        // This ensures zones are hidden even if flagsChanged events are missed
        modifierStateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ModifierStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let modifiers = notification.userInfo?["modifiers"] as? UInt {
                let flags = NSEvent.ModifierFlags(rawValue: modifiers)
                let normalized = flags.normalized
                if normalized.isEmpty {
                    // Debounce: schedule hide instead of immediate, lets rapid key
                    // transitions settle before deciding to hide
                    self?.scheduleHide()
                }
            }
        }

        // Listen for zone dimension changes to rebuild windows
        dimensionChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("zoneDimensionsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildZoneWindows()
        }
    }

    deinit {
        cleanup()
    }

    private func cleanup() {
        hideTimer?.invalidate()
        hideTimer = nil
        modifierCheckTimer?.invalidate()
        modifierCheckTimer = nil

        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
        if let observer = dimensionChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            dimensionChangeObserver = nil
        }
        if let observer = modifierStateObserver {
            NotificationCenter.default.removeObserver(observer)
            modifierStateObserver = nil
        }
        for observer in appEventObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        appEventObservers.removeAll()
        if let monitor = modifierMonitor {
            NSEvent.removeMonitor(monitor)
            modifierMonitor = nil
        }
        if let monitor = localModifierMonitor {
            NSEvent.removeMonitor(monitor)
            localModifierMonitor = nil
        }

        closeAllWindows()
    }

    private func closeAllWindows() {
        for (_, window) in zoneWindows {
            window.close()
        }
        zoneWindows.removeAll()
    }

    // MARK: - Public Interface

    /// Show zone highlights in preview mode (all zones visible regardless of gestures)
    func showPreview(duration: TimeInterval = 5.0) {
        guard let screen = NSScreen.main else { return }

        // Cancel any pending hide
        hideTimer?.invalidate()
        hideTimer = nil
        isHiding = false

        // Show all zones in inactive state (no gesture matching)
        for zone in ScreenZone.allCases {
            let frame = frameForZone(zone, screen: screen)

            // Create window on demand
            if zoneWindows[zone] == nil {
                zoneWindows[zone] = ZoneWindow(zone: zone, frame: frame)
            }

            guard let window = zoneWindows[zone] else { continue }

            // Update frame if screen changed
            if window.frame != frame {
                window.setFrame(frame, display: true)
            }

            // Preview mode: show zones without labels
            window.updateState(isActive: false, label: nil)
            window.animations = [:]
            window.alphaValue = 1.0
            window.orderFront(nil)
        }

        // Auto-hide after duration
        if duration > 0 {
            hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.hideZones()
            }
        }
    }

    func startHighlighting() {
        guard Configuration.shared.showZoneHighlights else { return }

        startModifierMonitoring()

        // Clean up any previous app event observers to prevent buildup
        for observer in appEventObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        appEventObservers.removeAll()

        // Hide zones when app becomes inactive or enters fullscreen
        appEventObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideZones()
        })

        appEventObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideZones()
        })

        // Also hide on space change which can miss modifier releases
        appEventObservers.append(NotificationCenter.default.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            self?.hideZones()
        })

        if screenChangeObserver == nil {
            screenChangeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.screenDidChange()
            }
        }

        // Start periodic modifier check as a fallback for stuck highlights
        startModifierCheckTimer()
    }

    func stopHighlighting() {
        stopModifierMonitoring()
        modifierCheckTimer?.invalidate()
        modifierCheckTimer = nil
        closeAllWindows()

        for observer in appEventObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        appEventObservers.removeAll()

        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
    }

    // MARK: - Zone Frame Calculations

    private func frameForZone(_ zone: ScreenZone, screen: NSScreen) -> NSRect {
        let config = Configuration.shared
        let threshold = config.edgeThreshold
        let cornerSize = config.cornerSize
        let cornerBuffer = config.cornerBuffer
        let screenFrame = screen.frame
        let menuBarHeight: CGFloat = 38
        let adjustedMaxY = screenFrame.maxY - menuBarHeight

        switch zone {
        case .topLeft:
            return NSRect(x: screenFrame.minX, y: adjustedMaxY - cornerSize,
                         width: cornerSize, height: cornerSize)
        case .top:
            let left = screenFrame.minX + cornerSize + cornerBuffer
            let right = screenFrame.maxX - cornerSize - cornerBuffer
            return NSRect(x: left, y: adjustedMaxY - threshold,
                         width: right - left, height: threshold)
        case .topRight:
            return NSRect(x: screenFrame.maxX - cornerSize, y: adjustedMaxY - cornerSize,
                         width: cornerSize, height: cornerSize)
        case .left:
            let top = adjustedMaxY - cornerSize - cornerBuffer
            let bottom = screenFrame.minY + cornerSize + cornerBuffer
            return NSRect(x: screenFrame.minX, y: bottom,
                         width: threshold, height: top - bottom)
        case .right:
            let top = adjustedMaxY - cornerSize - cornerBuffer
            let bottom = screenFrame.minY + cornerSize + cornerBuffer
            return NSRect(x: screenFrame.maxX - threshold, y: bottom,
                         width: threshold, height: top - bottom)
        case .bottomLeft:
            return NSRect(x: screenFrame.minX, y: screenFrame.minY,
                         width: cornerSize, height: cornerSize)
        case .bottom:
            let left = screenFrame.minX + cornerSize + cornerBuffer
            let right = screenFrame.maxX - cornerSize - cornerBuffer
            return NSRect(x: left, y: screenFrame.minY,
                         width: right - left, height: threshold)
        case .bottomRight:
            return NSRect(x: screenFrame.maxX - cornerSize, y: screenFrame.minY,
                         width: cornerSize, height: cornerSize)
        }
    }

    // MARK: - Window Management

    private func showZones(modifiers: NSEvent.ModifierFlags) {
        guard let screen = NSScreen.main else { return }
        let config = Configuration.shared

        // Cancel any pending hide
        hideTimer?.invalidate()
        hideTimer = nil
        isHiding = false

        for zone in ScreenZone.allCases {
            let frame = frameForZone(zone, screen: screen)

            // Create window on demand
            if zoneWindows[zone] == nil {
                zoneWindows[zone] = ZoneWindow(zone: zone, frame: frame)
            }

            guard let window = zoneWindows[zone] else { continue }

            // Update frame if screen changed
            if window.frame != frame {
                window.setFrame(frame, display: true)
            }

            // Check if zone has active gesture
            let gesture = config.gestures.first { g in
                g.zone == zone &&
                g.modifiers == modifiers &&
                g.isEnabled &&
                g.hasZoneTrigger
            }

            let isActive = gesture != nil
            // Show assigned action name only for zones with matching gestures
            let label: String? = isActive ? getLabel(for: gesture) : nil

            window.updateState(isActive: isActive, label: label)
            // Cancel any running fade-out animation before making visible
            window.animations = [:]
            window.alphaValue = 1.0
            window.orderFront(nil)
        }
    }

    /// Schedule a debounced hide that verifies real modifier state before hiding.
    /// This prevents flashing when modifiers are pressed in rapid succession.
    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // Re-check actual system modifier state before hiding - rapid key
            // transitions may have restored modifiers since the hide was scheduled
            let realMods = NSEvent.ModifierFlags.currentSystem
            guard realMods.isEmpty else {
                // Modifiers are held again; update state and keep zones visible
                self.currentModifiers = realMods
                return
            }
            self.currentModifiers = []
            self.hideZones()
        }
    }

    private func hideZones() {
        guard !isHiding else { return }
        isHiding = true
        let generation = hideGeneration
        hideGeneration &+= 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            for (_, window) in zoneWindows {
                window.animator().alphaValue = 0.0
            }
        } completionHandler: { [weak self] in
            guard let self = self else { return }
            // Only close if this hide wasn't superseded (by a new show that set
            // isHiding=false, or by a newer hide with a different generation).
            // The generation check supersedes the old isHiding-only check: a
            // second hide sets isHiding=true again, which would have let the
            // FIRST completion close windows mid-second-fade.
            guard self.isHiding, self.hideGeneration == generation else { return }
            self.closeAllWindows()
            self.isHiding = false
        }
    }

    private func getLabel(for gesture: Gesture?) -> String? {
        guard let gesture = gesture else { return nil }

        // Priority 1: Gesture Title (if user provided one)
        if let name = gesture.name, !name.isEmpty {
            return name
        }

        // Priority 2: Special case: show shortcut name for run_shortcut
        if gesture.actionIdentifier == "com.mousegestures.automation.run_shortcut",
           let name = gesture.parameters["shortcut_name"]?.value as? String {
            return name
        }

        // Priority 3: Look up action name from plugin registry
        if let (_, action) = PluginManager.shared.getAction(identifier: gesture.actionIdentifier) {
            return action.name
        }

        // Fallback: extract readable name from action identifier
        // e.g. "com.mousegestures.core.close_window" -> "Close Window"
        let lastComponent = gesture.actionIdentifier.split(separator: ".").last.map(String.init) ?? gesture.actionIdentifier
        return lastComponent
            .replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized
    }

    private func refreshZoneStates() {
        if !currentModifiers.isEmpty && !zoneWindows.isEmpty {
            showZones(modifiers: currentModifiers)
        }
    }

    private func screenDidChange() {
        closeAllWindows()
    }

    // MARK: - Zone Rebuilding

    /// Rebuild all zone windows when dimensions change
    private func rebuildZoneWindows() {
        let wasShowing = !zoneWindows.isEmpty && zoneWindows.values.contains(where: { $0.isVisible })
        closeAllWindows()
        // If zones were visible, re-show them with updated dimensions
        if wasShowing && !currentModifiers.isEmpty {
            showZones(modifiers: currentModifiers)
        }
    }

    // MARK: - Stuck Highlight Protection

    /// Periodically checks if modifiers are still held; hides zones if they were released
    /// without the event being captured (e.g., during fullscreen transitions)
    private func startModifierCheckTimer() {
        modifierCheckTimer?.invalidate()
        modifierCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let realModifiers = NSEvent.ModifierFlags.currentSystem
            if realModifiers.isEmpty && !self.currentModifiers.isEmpty {
                self.currentModifiers = []
                self.scheduleHide()
            }
        }
    }

    // MARK: - Modifier Monitoring

    private func startModifierMonitoring() {
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierChange(event)
        }
        // Also monitor locally so modifier changes are tracked when app window is focused
        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierChange(event)
            return event
        }
    }

    private func stopModifierMonitoring() {
        if let monitor = modifierMonitor {
            NSEvent.removeMonitor(monitor)
            modifierMonitor = nil
        }
        if let monitor = localModifierMonitor {
            NSEvent.removeMonitor(monitor)
            localModifierMonitor = nil
        }
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func handleModifierChange(_ event: NSEvent) {
        guard Configuration.shared.showZoneHighlights else { return }

        let modifiers = event.modifierFlags.normalized
        currentModifiers = modifiers

        if !modifiers.isEmpty {
            // Cancel any pending hide since modifiers are held
            hideTimer?.invalidate()
            hideTimer = nil

            let hasMatchingGestures = Configuration.shared.gestures.contains { g in
                g.modifiers == modifiers &&
                g.isEnabled &&
                g.hasZoneTrigger
            }

            if hasMatchingGestures {
                showZones(modifiers: modifiers)
            }
        } else {
            scheduleHide()
        }
    }

    // Modifier normalization uses shared NSEvent.ModifierFlags.normalized
    // from Extensions.swift.
}

// MARK: - Legacy Compatibility (Unused but kept for reference)

/// Legacy full-screen window - kept for reference but no longer used
/// Memory cost was ~60MB on Retina displays due to full-screen backing store
@available(*, deprecated, message: "Use ZoneHighlightManager with individual ZoneWindows instead")
class ZoneHighlightWindow: NSWindow {
    private var highlightView: ZoneHighlightView?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = NSColor.clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        highlightView = ZoneHighlightView(frame: frame)
        contentView = highlightView
    }

    override func close() {
        highlightView = nil
        super.close()
    }

    func showZones(withModifiers modifiers: NSEvent.ModifierFlags = []) {
        if let screen = NSScreen.main {
            setFrame(screen.frame, display: true)
            highlightView?.frame = screen.frame
        }
        highlightView?.currentModifiers = modifiers
        highlightView?.needsDisplay = true
        orderFront(nil)
        alphaValue = 1.0
    }

    func hideZones() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
        }
    }

    func updateModifiers(_ modifiers: NSEvent.ModifierFlags) {
        if let screen = NSScreen.main {
            setFrame(screen.frame, display: true)
            highlightView?.frame = screen.frame
        }
        highlightView?.currentModifiers = modifiers
        highlightView?.needsDisplay = true
    }
}

/// Legacy full-screen view - kept for reference
@available(*, deprecated, message: "Use ZoneView instead")
class ZoneHighlightView: NSView {
    var currentModifiers: NSEvent.ModifierFlags = []

    private let inactiveColor = NSColor.systemBlue.withAlphaComponent(0.1)
    private let activeColor = NSColor.systemGreen.withAlphaComponent(0.3)
    private let borderColor = NSColor.white.withAlphaComponent(0.5)

    override func draw(_ dirtyRect: NSRect) {
        // Minimal implementation for compatibility
    }
}
