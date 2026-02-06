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
    
    func updateState(isActive: Bool, label: String?) {
        zoneView?.isActive = isActive
        zoneView?.label = label
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
    
    private let inactiveColor = NSColor.systemBlue.withAlphaComponent(0.1)
    private let activeColor = NSColor.systemGreen.withAlphaComponent(0.3)
    private let borderColor = NSColor.white.withAlphaComponent(0.5)
    
    init(frame: NSRect, zone: ScreenZone) {
        self.zone = zone
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Fill the entire view (the window is already sized to the zone)
        let fillColor = isActive ? activeColor : inactiveColor
        fillColor.setFill()
        bounds.fill()
        
        // Draw border
        borderColor.setStroke()
        let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        borderPath.lineWidth = 1.0
        borderPath.stroke()
        
        // Draw label if present
        if let label = label, Configuration.shared.showZoneLabels {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
                .strokeColor: NSColor.black,
                .strokeWidth: -2.0
            ]
            let size = label.size(withAttributes: attrs)
            let point = NSPoint(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2
            )
            label.draw(at: point, withAttributes: attrs)
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
    private var currentModifiers: NSEvent.ModifierFlags = []
    
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
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ModifierStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let modifiers = notification.userInfo?["modifiers"] as? UInt {
                let flags = NSEvent.ModifierFlags(rawValue: modifiers)
                let normalized = self?.normalizeModifiers(flags) ?? []
                if normalized.isEmpty {
                    self?.hideZones()
                }
            }
        }
    }
    
    deinit {
        cleanup()
    }
    
    private func cleanup() {
        hideTimer?.invalidate()
        hideTimer = nil
        
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
        if let monitor = modifierMonitor {
            NSEvent.removeMonitor(monitor)
            modifierMonitor = nil
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
    
    func startHighlighting() {
        guard Configuration.shared.showZoneHighlights else { return }
        
        startModifierMonitoring()
        
        // Hide zones when app becomes inactive or enters fullscreen
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideZones()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideZones()
        }
        guard Configuration.shared.showZoneHighlights else { return }
        
        startModifierMonitoring()
        
        if screenChangeObserver == nil {
            screenChangeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.screenDidChange()
            }
        }
    }
    
    func stopHighlighting() {
        stopModifierMonitoring()
        closeAllWindows()
        
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
                (g.activationType == .gesture || g.activationType == .both)
            }
            
            let isActive = gesture != nil
            let label = getLabel(for: gesture)
            
            window.updateState(isActive: isActive, label: label)
            window.orderFront(nil)
            window.alphaValue = 1.0
        }
    }
    
    private func hideZones() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            for (_, window) in zoneWindows {
                window.animator().alphaValue = 0.0
            }
        } completionHandler: { [weak self] in
            for (_, window) in self?.zoneWindows ?? [:] {
                window.orderOut(nil)
            }
        }
    }
    
    private func getLabel(for gesture: Gesture?) -> String? {
        guard let gesture = gesture else { return nil }
        
        if gesture.actionIdentifier == "com.mousegestures.automation.run_shortcut",
           let name = gesture.parameters["shortcut_name"]?.value as? String {
            return name
        }
        
        if let (_, action) = PluginManager.shared.getAction(identifier: gesture.actionIdentifier) {
            return action.name
        }
        
        return nil
    }
    
    private func refreshZoneStates() {
        if !currentModifiers.isEmpty && !zoneWindows.isEmpty {
            showZones(modifiers: currentModifiers)
        }
    }
    
    private func screenDidChange() {
        closeAllWindows()
    }
    
    // MARK: - Modifier Monitoring
    
    private func startModifierMonitoring() {
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierChange(event)
        }
    }
    
    private func stopModifierMonitoring() {
        if let monitor = modifierMonitor {
            NSEvent.removeMonitor(monitor)
            modifierMonitor = nil
        }
        hideTimer?.invalidate()
        hideTimer = nil
    }
    
    private func handleModifierChange(_ event: NSEvent) {
        guard Configuration.shared.showZoneHighlights else { return }
        
        let modifiers = normalizeModifiers(event.modifierFlags)
        currentModifiers = modifiers
        
        hideTimer?.invalidate()
        hideTimer = nil
        
        if !modifiers.isEmpty {
            let hasMatchingGestures = Configuration.shared.gestures.contains { g in
                g.modifiers == modifiers &&
                g.isEnabled &&
                (g.activationType == .gesture || g.activationType == .both)
            }
            
            if hasMatchingGestures {
                showZones(modifiers: modifiers)
            }
        } else {
            hideTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                self?.hideZones()
            }
        }
    }
    
    private func normalizeModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        var normalized: NSEvent.ModifierFlags = []
        if flags.contains(.command) { normalized.insert(.command) }
        if flags.contains(.control) { normalized.insert(.control) }
        if flags.contains(.option) { normalized.insert(.option) }
        if flags.contains(.shift) { normalized.insert(.shift) }
        return normalized
    }
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
