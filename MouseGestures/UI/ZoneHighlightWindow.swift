import Cocoa

// Window for showing gesture zone highlights
class ZoneHighlightWindow: NSWindow {
    private var highlightView: ZoneHighlightView!
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
        
        setupWindow()
        setupHighlightView()
    }
    
    private func setupWindow() {
        // Make window transparent and non-interactive
        isOpaque = false
        backgroundColor = NSColor.clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        
        // Make sure it stays on all spaces
        isReleasedWhenClosed = false
    }
    
    private func setupHighlightView() {
        highlightView = ZoneHighlightView(frame: frame)
        contentView = highlightView
    }
    
    func showZones(withModifiers modifiers: NSEvent.ModifierFlags = []) {
        // Update frame to match current screen
        if let screen = NSScreen.main {
            setFrame(screen.frame, display: true)
            highlightView.frame = screen.frame
        }
        highlightView.currentModifiers = modifiers
        highlightView.needsDisplay = true
        orderFront(nil)
        alphaValue = 1.0
    }
    
    func hideZones() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = 0.0
        } completionHandler: {
            self.orderOut(nil)
        }
    }
    
    func updateModifiers(_ modifiers: NSEvent.ModifierFlags) {
        // Update frame to match current screen
        if let screen = NSScreen.main {
            setFrame(screen.frame, display: true)
            highlightView.frame = screen.frame
        }
        highlightView.currentModifiers = modifiers
        highlightView.needsDisplay = true
    }
}

// Custom view for drawing zone highlights
class ZoneHighlightView: NSView {
    var currentModifiers: NSEvent.ModifierFlags = []
    
    // Colors for different zone states
    private let inactiveColor = NSColor.systemBlue.withAlphaComponent(0.1)
    private let activeColor = NSColor.systemGreen.withAlphaComponent(0.3)
    private let hoverColor = NSColor.systemYellow.withAlphaComponent(0.4)
    private let borderColor = NSColor.white.withAlphaComponent(0.5)
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let screen = NSScreen.main else { return }
        let config = Configuration.shared
        
        // Draw all zones
        for zone in ScreenZone.allCases {
            drawZone(zone, 
                    screenFrame: screen.frame,
                    threshold: config.edgeThreshold,
                    cornerSize: config.cornerSize,
                    cornerBuffer: config.cornerBuffer)
        }
        
        // Draw labels if enabled
        if config.showZoneLabels {
            drawZoneLabels(screenFrame: screen.frame,
                          threshold: config.edgeThreshold,
                          cornerSize: config.cornerSize,
                          cornerBuffer: config.cornerBuffer)
        }
    }
    
    private func drawZone(_ zone: ScreenZone, screenFrame: NSRect, threshold: CGFloat, cornerSize: CGFloat, cornerBuffer: CGFloat) {
        let zonePath = createPath(for: zone, screenFrame: screenFrame, threshold: threshold, cornerSize: cornerSize, cornerBuffer: cornerBuffer)
        
        // Check if this zone has an active gesture for current modifiers
        let hasActiveGesture = Configuration.shared.gestures.contains { gesture in
            gesture.zone == zone &&
            gesture.modifiers == currentModifiers &&
            gesture.isEnabled &&
            (gesture.activationType == .gesture || gesture.activationType == .both)
        }
        
        // Set fill color based on state
        if hasActiveGesture {
            activeColor.setFill()
        } else {
            inactiveColor.setFill()
        }
        
        zonePath.fill()
        
        // Draw border
        borderColor.setStroke()
        zonePath.lineWidth = 1.0
        zonePath.stroke()
    }
    
    private func createPath(for zone: ScreenZone, screenFrame: NSRect, threshold: CGFloat, cornerSize: CGFloat, cornerBuffer: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        
        // Account for menu bar height
        let menuBarHeight: CGFloat = 38
        let adjustedMaxY = screenFrame.maxY - menuBarHeight
        
        switch zone {
        case .topLeft:
            path.move(to: NSPoint(x: screenFrame.minX, y: adjustedMaxY))
            path.line(to: NSPoint(x: screenFrame.minX + cornerSize, y: adjustedMaxY))
            path.line(to: NSPoint(x: screenFrame.minX + cornerSize, y: adjustedMaxY - cornerSize))
            path.line(to: NSPoint(x: screenFrame.minX, y: adjustedMaxY - cornerSize))
            path.close()
            
        case .top:
            let leftBoundary = screenFrame.minX + cornerSize + cornerBuffer
            let rightBoundary = screenFrame.maxX - cornerSize - cornerBuffer
            path.move(to: NSPoint(x: leftBoundary, y: adjustedMaxY))
            path.line(to: NSPoint(x: rightBoundary, y: adjustedMaxY))
            path.line(to: NSPoint(x: rightBoundary, y: adjustedMaxY - threshold))
            path.line(to: NSPoint(x: leftBoundary, y: adjustedMaxY - threshold))
            path.close()
            
        case .topRight:
            path.move(to: NSPoint(x: screenFrame.maxX - cornerSize, y: adjustedMaxY))
            path.line(to: NSPoint(x: screenFrame.maxX, y: adjustedMaxY))
            path.line(to: NSPoint(x: screenFrame.maxX, y: adjustedMaxY - cornerSize))
            path.line(to: NSPoint(x: screenFrame.maxX - cornerSize, y: adjustedMaxY - cornerSize))
            path.close()
            
        case .left:
            let menuBarHeight: CGFloat = 25
            let topBoundary = (screenFrame.maxY - menuBarHeight) - cornerSize - cornerBuffer
            let bottomBoundary = screenFrame.minY + cornerSize + cornerBuffer
            path.move(to: NSPoint(x: screenFrame.minX, y: topBoundary))
            path.line(to: NSPoint(x: screenFrame.minX + threshold, y: topBoundary))
            path.line(to: NSPoint(x: screenFrame.minX + threshold, y: bottomBoundary))
            path.line(to: NSPoint(x: screenFrame.minX, y: bottomBoundary))
            path.close()
            
        case .right:
            let menuBarHeight: CGFloat = 25
            let topBoundary = (screenFrame.maxY - menuBarHeight) - cornerSize - cornerBuffer
            let bottomBoundary = screenFrame.minY + cornerSize + cornerBuffer
            path.move(to: NSPoint(x: screenFrame.maxX - threshold, y: topBoundary))
            path.line(to: NSPoint(x: screenFrame.maxX, y: topBoundary))
            path.line(to: NSPoint(x: screenFrame.maxX, y: bottomBoundary))
            path.line(to: NSPoint(x: screenFrame.maxX - threshold, y: bottomBoundary))
            path.close()
            
        case .bottomLeft:
            path.move(to: NSPoint(x: screenFrame.minX, y: screenFrame.minY))
            path.line(to: NSPoint(x: screenFrame.minX, y: screenFrame.minY + cornerSize))
            path.line(to: NSPoint(x: screenFrame.minX + cornerSize, y: screenFrame.minY + cornerSize))
            path.line(to: NSPoint(x: screenFrame.minX + cornerSize, y: screenFrame.minY))
            path.close()
            
        case .bottom:
            let leftBoundary = screenFrame.minX + cornerSize + cornerBuffer
            let rightBoundary = screenFrame.maxX - cornerSize - cornerBuffer
            path.move(to: NSPoint(x: leftBoundary, y: screenFrame.minY))
            path.line(to: NSPoint(x: leftBoundary, y: screenFrame.minY + threshold))
            path.line(to: NSPoint(x: rightBoundary, y: screenFrame.minY + threshold))
            path.line(to: NSPoint(x: rightBoundary, y: screenFrame.minY))
            path.close()
            
        case .bottomRight:
            path.move(to: NSPoint(x: screenFrame.maxX - cornerSize, y: screenFrame.minY))
            path.line(to: NSPoint(x: screenFrame.maxX - cornerSize, y: screenFrame.minY + cornerSize))
            path.line(to: NSPoint(x: screenFrame.maxX, y: screenFrame.minY + cornerSize))
            path.line(to: NSPoint(x: screenFrame.maxX, y: screenFrame.minY))
            path.close()
        }
        
        return path
    }
    
    private func drawZoneLabels(screenFrame: NSRect, threshold: CGFloat, cornerSize: CGFloat, cornerBuffer: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -2.0
        ]
        
        for zone in ScreenZone.allCases {
            let label = getZoneLabel(for: zone)
            let labelSize = label.size(withAttributes: attributes)
            let labelPoint = getLabelPosition(for: zone, screenFrame: screenFrame, 
                                             labelSize: labelSize, threshold: threshold, 
                                             cornerSize: cornerSize, cornerBuffer: cornerBuffer)
            
            label.draw(at: labelPoint, withAttributes: attributes)
        }
    }
    
    private func getZoneLabel(for zone: ScreenZone) -> String {
        // Check if zone has active gesture
        if let gesture = Configuration.shared.gestures.first(where: { 
            $0.zone == zone && 
            $0.modifiers == currentModifiers && 
            $0.isEnabled &&
            ($0.activationType == .gesture || $0.activationType == .both)
        }) {
            // Show the action for this zone
            // Check if this is a runShortcut action
            if gesture.actionIdentifier == "com.mousegestures.automation.run_shortcut",
               let name = gesture.parameters["shortcut_name"]?.value as? String {
                return name
            } else {
                // Get plugin action name from the identifier
                if let (_, action) = PluginManager.shared.getAction(identifier: gesture.actionIdentifier) {
                    return action.name
                } else {
                    return gesture.actionIdentifier // Fallback to raw identifier
                }
            }
        }
        
        // Show zone name if no active gesture
        switch zone {
        case .topLeft: return "↖"
        case .top: return "↑"
        case .topRight: return "↗"
        case .left: return "←"
        case .right: return "→"
        case .bottomLeft: return "↙"
        case .bottom: return "↓"
        case .bottomRight: return "↘"
        }
    }
    
    private func getLabelPosition(for zone: ScreenZone, screenFrame: NSRect, labelSize: NSSize, 
                                  threshold: CGFloat, cornerSize: CGFloat, cornerBuffer: CGFloat) -> NSPoint {
        // Account for menu bar height
        let menuBarHeight: CGFloat = 25
        let adjustedMaxY = screenFrame.maxY - menuBarHeight
        let padding: CGFloat = 5
        
        switch zone {
        case .topLeft:
            return NSPoint(x: screenFrame.minX + padding, 
                          y: adjustedMaxY - cornerSize/2 - labelSize.height/2)
        case .top:
            return NSPoint(x: screenFrame.midX - labelSize.width/2, 
                          y: adjustedMaxY - threshold/2 - labelSize.height/2)
        case .topRight:
            // Keep label inside the zone, aligned to the right edge minus padding and label width
            return NSPoint(x: screenFrame.maxX - labelSize.width - padding, 
                          y: adjustedMaxY - cornerSize/2 - labelSize.height/2)
        case .left:
            return NSPoint(x: screenFrame.minX + padding, 
                          y: screenFrame.midY - labelSize.height/2)
        case .right:
            // Keep label inside the zone, aligned to the right edge minus padding and label width
            return NSPoint(x: screenFrame.maxX - labelSize.width - padding, 
                          y: screenFrame.midY - labelSize.height/2)
        case .bottomLeft:
            return NSPoint(x: screenFrame.minX + padding, 
                          y: screenFrame.minY + cornerSize/2 - labelSize.height/2)
        case .bottom:
            return NSPoint(x: screenFrame.midX - labelSize.width/2, 
                          y: screenFrame.minY + threshold/2 - labelSize.height/2)
        case .bottomRight:
            // Keep label inside the zone, aligned to the right edge minus padding and label width
            return NSPoint(x: screenFrame.maxX - labelSize.width - padding, 
                          y: screenFrame.minY + cornerSize/2 - labelSize.height/2)
        }
    }
}

// Manager for controlling zone highlights
class ZoneHighlightManager {
    static let shared = ZoneHighlightManager()
    private var highlightWindow: ZoneHighlightWindow?
    private var modifierMonitor: Any?
    private var hideTimer: Timer?
    private var configChangeObserver: Any?
    
    private init() {
        // Listen for configuration changes to refresh the window
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GestureConfigurationChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshHighlightWindow()
        }
    }
    
    deinit {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func refreshHighlightWindow() {
        // If highlights are visible, refresh the window frame
        if highlightWindow?.isVisible == true {
            if let screen = NSScreen.main {
                highlightWindow?.setFrame(screen.frame, display: true)
                highlightWindow?.contentView?.frame = screen.frame
                highlightWindow?.contentView?.needsDisplay = true
            }
        }
    }
    
    func startHighlighting() {
        guard Configuration.shared.showZoneHighlights else { return }
        
        // Create highlight window if needed
        if highlightWindow == nil {
            if let screen = NSScreen.main {
                highlightWindow = ZoneHighlightWindow(contentRect: screen.frame,
                                                     styleMask: .borderless,
                                                     backing: .buffered,
                                                     defer: false)
            }
        }
        
        // Start monitoring modifier keys
        startModifierMonitoring()
        
        // Also start monitoring for screen changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    @objc private func screenDidChange(_ notification: Notification) {
        // Recreate highlight window with new screen dimensions
        if let screen = NSScreen.main {
            highlightWindow = ZoneHighlightWindow(contentRect: screen.frame,
                                                 styleMask: .borderless,
                                                 backing: .buffered,
                                                 defer: false)
        }
    }
    
    func stopHighlighting() {
        stopModifierMonitoring()
        highlightWindow?.hideZones()
        highlightWindow = nil
        
        // Remove screen change observer
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    private func startModifierMonitoring() {
        // Monitor modifier key changes
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
        let config = Configuration.shared
        guard config.showZoneHighlights else { return }
        
        let modifiers = normalizeModifiers(event.modifierFlags)
        
        // Cancel any pending hide timer
        hideTimer?.invalidate()
        hideTimer = nil
        
        if !modifiers.isEmpty {
            // Check if we should show highlights based on settings
            let shouldShow: Bool
            
            // Simplified logic - show if there are active gestures for these modifiers
            shouldShow = config.gestures.contains { gesture in
                gesture.modifiers == modifiers &&
                gesture.isEnabled &&
                (gesture.activationType == .gesture || gesture.activationType == .both)
            }
            
            if shouldShow {
                // Ensure window is on correct screen and properly sized
                if let screen = NSScreen.main {
                    // Recreate window if screen changed significantly
                    if highlightWindow == nil || !highlightWindow!.frame.equalTo(screen.frame) {
                        highlightWindow = ZoneHighlightWindow(contentRect: screen.frame,
                                                             styleMask: .borderless,
                                                             backing: .buffered,
                                                             defer: false)
                    }
                }
                
                // Force window to front even if already visible
                highlightWindow?.orderFront(nil)
                highlightWindow?.alphaValue = 1.0
                highlightWindow?.showZones(withModifiers: modifiers)
                highlightWindow?.updateModifiers(modifiers)
                
                // Hide timer removed - highlights stay while modifiers are held
            }
        } else {
            // All modifiers released - hide highlights with a small delay to prevent flicker
            hideTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                self?.highlightWindow?.hideZones()
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

