import Cocoa

/// All pointer-motion triggers behind one event monitor: shakes, circles and corner dwell.
public final class PointerGesturesPlugin: NSObject, ExternalTriggerPlugin, ExternalTriggerBindingAware, ExternalTriggerOptionsProviding, PluginExtension {
    public var identifier: String { "com.mousegestures.pointer" }
    public var name: String { "Pointer Gestures" }
    public var summary: String { "Shake, circle or rest the pointer in a corner" }
    public var version: String { "1.0.0" }
    public var author: String { "MouseGestures" }
    public var icon: String { "cursorarrow.motionlines" }
    public var triggers: [ExternalTriggerDefinition] {[
        ExternalTriggerDefinition(id: "shake_horizontal", name: "Shake left and right", summary: "Several quick direction changes sideways"),
        ExternalTriggerDefinition(id: "shake_vertical", name: "Shake up and down", summary: "Several quick direction changes vertically"),
        ExternalTriggerDefinition(id: "circle_cw", name: "Circle (clockwise)", summary: "Draw a loop clockwise"),
        ExternalTriggerDefinition(id: "circle_ccw", name: "Circle (counter-clockwise)", summary: "Draw a loop counter-clockwise"),
        ExternalTriggerDefinition(id: "corner_top_left", name: "Rest in top-left corner", summary: "Dwell in the corner"),
        ExternalTriggerDefinition(id: "corner_top_right", name: "Rest in top-right corner", summary: "Dwell in the corner"),
        ExternalTriggerDefinition(id: "corner_bottom_left", name: "Rest in bottom-left corner", summary: "Dwell in the corner"),
        ExternalTriggerDefinition(id: "corner_bottom_right", name: "Rest in bottom-right corner", summary: "Dwell in the corner"),
    ]}

    public func options(forTrigger id: String) -> [PluginSettingField] {
        let keys: [String]
        switch id {
        case "shake_horizontal", "shake_vertical": keys = ["modifier", "reversals", "minStroke", "shakeWindow"]
        case "circle_cw", "circle_ccw": keys = ["modifier", "minSize", "circleWindow"]
        default: keys = id.hasPrefix("corner_") ? ["dwell", "cornerSize"] : []
        }
        return keys.compactMap { k in settingsFields.first { $0.key == k } }
    }

    private var settings: PluginHost?
    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "modifier", title: "Hold a modifier for shakes and circles",
                           kind: .choice([PluginSettingChoice("none", "None (always on)"), PluginSettingChoice("option", "⌥ Option"),
                                          PluginSettingChoice("control", "⌃ Control"), PluginSettingChoice("shift", "⇧ Shift"), PluginSettingChoice("command", "⌘ Command")]),
                           defaultValue: AnyCodable("none"), help: "Only recognise shakes and circles while this key is held. Recommended if they trigger by accident. Corners are unaffected."),
        PluginSettingField(key: "reversals", title: "Shake: direction changes needed", kind: .number(min: 3, max: 10, step: 1, unit: nil),
                           defaultValue: AnyCodable(4), help: "Lower = easier to trigger."),
        PluginSettingField(key: "minStroke", title: "Shake: minimum stroke length", kind: .number(min: 20, max: 300, step: 10, unit: "pt"),
                           defaultValue: AnyCodable(70), help: "Each swing must travel at least this far, so tiny jitters are ignored."),
        PluginSettingField(key: "shakeWindow", title: "Shake: time window", kind: .number(min: 0.3, max: 2, step: 0.1, unit: "s"),
                           defaultValue: AnyCodable(0.8), help: "All the swings must happen within this time."),
        PluginSettingField(key: "minSize", title: "Circle: minimum size", kind: .number(min: 40, max: 400, step: 10, unit: "pt"),
                           defaultValue: AnyCodable(90), help: "Smaller loops are ignored."),
        PluginSettingField(key: "circleWindow", title: "Circle: time allowed", kind: .number(min: 0.4, max: 3, step: 0.1, unit: "s"),
                           defaultValue: AnyCodable(1.4), help: "The whole loop must be drawn within this time."),
        PluginSettingField(key: "dwell", title: "Corner: dwell time", kind: .number(min: 0.3, max: 3, step: 0.1, unit: "s"),
                           defaultValue: AnyCodable(0.9), help: "How long the pointer must rest in the corner."),
        PluginSettingField(key: "cornerSize", title: "Corner: size", kind: .number(min: 2, max: 40, step: 2, unit: "pt"),
                           defaultValue: AnyCodable(6), help: "Size of the hot area at each screen corner."),
    ]}
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }

    private var monitor: Any?
    private weak var host: ExternalTriggerHost?
    private var bindings: [ExternalTriggerBinding] = []
    private var samples: [(p: CGPoint, t: TimeInterval)] = []
    private var lastFire: TimeInterval = 0
    private let spacing: CGFloat = 6
    private let cooldown: TimeInterval = 1.2
    private var cornerTimers: [String: Timer] = [:]      // binding key → pending dwell timer
    private var firedCorners = Set<String>()             // fired while the pointer is still resting there

    private func fire(_ b: ExternalTriggerBinding) {
        if let h = host as? ExternalTriggerBindingHost { h.fire(binding: b) } else { host?.fire(triggerId: b.triggerId) }
    }

    private func num(_ k: String, _ d: Double) -> Double { settings?.number(k, default: d) ?? d }
    /// A binding's own override if the gesture set one, else the plugin-wide setting.
    private func num(_ b: ExternalTriggerBinding, _ k: String, _ d: Double) -> Double { b.number(k, default: num(k, d)) }

    public func bindingsChanged(_ bindings: [ExternalTriggerBinding]) {
        self.bindings = bindings
        samples.removeAll()
        cornerTimers.values.forEach { $0.invalidate() }; cornerTimers.removeAll(); firedCorners.removeAll()
    }

    public func start(host: ExternalTriggerHost) throws {
        self.host = host
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.moved(NSEvent.mouseLocation, flags: NSEvent.modifierFlags)
        }
        host.log("Pointer Gestures started")
    }

    public func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil; host = nil; samples.removeAll(); bindings = []
        cornerTimers.values.forEach { $0.invalidate() }; cornerTimers.removeAll(); firedCorners.removeAll()
    }

    private func modifierHeld(_ f: NSEvent.ModifierFlags, _ b: ExternalTriggerBinding) -> Bool {
        switch b.string("modifier", default: settings?.string("modifier", default: "none") ?? "none") {
        case "option": return f.contains(.option)
        case "control": return f.contains(.control)
        case "shift": return f.contains(.shift)
        case "command": return f.contains(.command)
        default: return true
        }
    }

    private func moved(_ p: NSPoint, flags: NSEvent.ModifierFlags) {
        updateCorners(p)
        let active = bindings.filter { !$0.triggerId.hasPrefix("corner_") && modifierHeld(flags, $0) }
        guard !active.isEmpty else { samples.removeAll(); return }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = samples.last, hypot(p.x - last.p.x, p.y - last.p.y) < spacing { return }
        samples.append((p, now))
        let window = active.map { $0.triggerId.hasPrefix("shake") ? num($0, "shakeWindow", 0.8) : num($0, "circleWindow", 1.4) }.max() ?? 1.4
        samples.removeAll { now - $0.t > window }
        guard samples.count >= 6, now - lastFire > cooldown else { return }

        for b in active {
            let hit: Bool
            if b.triggerId.hasPrefix("shake") {
                let recent = samples.filter { now - $0.t <= num(b, "shakeWindow", 0.8) }.map { $0.p }
                hit = Recognizers.shake(recent, vertical: b.triggerId == "shake_vertical",
                                        reversalsNeeded: Int(num(b, "reversals", 4)), minStroke: CGFloat(num(b, "minStroke", 70)))
            } else {
                let pts = samples.filter { now - $0.t <= num(b, "circleWindow", 1.4) }.map { $0.p }
                hit = Recognizers.circle(pts, minSize: CGFloat(num(b, "minSize", 90))) == b.triggerId
            }
            if hit {
                lastFire = now
                samples.removeAll()
                fire(b)
                return
            }
        }
    }

    // MARK: corner dwell

    private func inCorner(_ id: String, at p: NSPoint, size: CGFloat) -> Bool {
        for s in NSScreen.screens where s.frame.insetBy(dx: -1, dy: -1).contains(p) {
            let f = s.frame
            let left = p.x - f.minX < size, right = f.maxX - p.x < size
            let bottom = p.y - f.minY < size, top = f.maxY - p.y < size
            switch id {
            case "corner_top_left": return left && top
            case "corner_top_right": return right && top
            case "corner_bottom_left": return left && bottom
            case "corner_bottom_right": return right && bottom
            default: return false
            }
        }
        return false
    }

    private func updateCorners(_ p: NSPoint) {
        for b in bindings where b.triggerId.hasPrefix("corner_") {
            let inside = inCorner(b.triggerId, at: p, size: CGFloat(num(b, "cornerSize", 6)))
            if !inside { cornerTimers.removeValue(forKey: b.key)?.invalidate(); firedCorners.remove(b.key); continue }
            guard cornerTimers[b.key] == nil, !firedCorners.contains(b.key) else { continue }
            cornerTimers[b.key] = Timer.scheduledTimer(withTimeInterval: num(b, "dwell", 0.9), repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.cornerTimers[b.key] = nil
                // The pointer must still be there; it re-arms only after leaving and re-entering.
                if self.inCorner(b.triggerId, at: NSEvent.mouseLocation, size: CGFloat(self.num(b, "cornerSize", 6))) {
                    self.firedCorners.insert(b.key)
                    self.fire(b)
                }
            }
        }
    }
}
