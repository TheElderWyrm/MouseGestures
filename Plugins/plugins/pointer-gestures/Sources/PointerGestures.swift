import Cocoa
import MouseGestures

/// All pointer-motion triggers behind one event monitor: shakes, circles and corner dwell.
@objc(PointerGesturesPlugin)
public final class PointerGesturesPlugin: NSObject, ExternalTriggerPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.pointergestures" }
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
    private var samples: [(p: CGPoint, t: TimeInterval)] = []
    private var lastFire: TimeInterval = 0
    private let spacing: CGFloat = 6
    private let cooldown: TimeInterval = 1.2
    private var currentCorner: String?
    private var cornerTimer: Timer?

    private func num(_ k: String, _ d: Double) -> Double { settings?.number(k, default: d) ?? d }

    public func start(host: ExternalTriggerHost) throws {
        self.host = host
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.moved(NSEvent.mouseLocation, flags: NSEvent.modifierFlags)
        }
        host.log("Pointer Gestures started")
    }

    public func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil; host = nil; samples.removeAll()
        cornerTimer?.invalidate(); cornerTimer = nil; currentCorner = nil
    }

    private func modifierHeld(_ f: NSEvent.ModifierFlags) -> Bool {
        switch settings?.string("modifier", default: "none") ?? "none" {
        case "option": return f.contains(.option)
        case "control": return f.contains(.control)
        case "shift": return f.contains(.shift)
        case "command": return f.contains(.command)
        default: return true
        }
    }

    private func moved(_ p: NSPoint, flags: NSEvent.ModifierFlags) {
        updateCorner(p)
        guard modifierHeld(flags) else { samples.removeAll(); return }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = samples.last, hypot(p.x - last.p.x, p.y - last.p.y) < spacing { return }
        samples.append((p, now))
        let window = max(num("circleWindow", 1.4), num("shakeWindow", 0.8))
        samples.removeAll { now - $0.t > window }
        guard samples.count >= 6, now - lastFire > cooldown else { return }

        let shakeWindow = num("shakeWindow", 0.8)
        let recent = samples.filter { now - $0.t <= shakeWindow }.map { $0.p }
        let reversals = Int(num("reversals", 4)), stroke = CGFloat(num("minStroke", 70))
        var id: String?
        if Recognizers.shake(recent, vertical: false, reversalsNeeded: reversals, minStroke: stroke) { id = "shake_horizontal" }
        else if Recognizers.shake(recent, vertical: true, reversalsNeeded: reversals, minStroke: stroke) { id = "shake_vertical" }
        else {
            let circleWindow = num("circleWindow", 1.4)
            let pts = samples.filter { now - $0.t <= circleWindow }.map { $0.p }
            id = Recognizers.circle(pts, minSize: CGFloat(num("minSize", 90)))
        }
        if let id = id {
            lastFire = now
            samples.removeAll()
            host?.fire(triggerId: id)
        }
    }

    // MARK: corner dwell

    private func corner(at p: NSPoint) -> String? {
        let size = CGFloat(num("cornerSize", 6))
        for s in NSScreen.screens where s.frame.insetBy(dx: -1, dy: -1).contains(p) {
            let f = s.frame
            let left = p.x - f.minX < size, right = f.maxX - p.x < size
            let bottom = p.y - f.minY < size, top = f.maxY - p.y < size
            switch (left, right, top, bottom) {
            case (true, _, true, _): return "corner_top_left"
            case (_, true, true, _): return "corner_top_right"
            case (true, _, _, true): return "corner_bottom_left"
            case (_, true, _, true): return "corner_bottom_right"
            default: return nil
            }
        }
        return nil
    }

    private func updateCorner(_ p: NSPoint) {
        let c = corner(at: p)
        guard c != currentCorner else { return }
        currentCorner = c
        cornerTimer?.invalidate(); cornerTimer = nil
        guard let c = c else { return }
        cornerTimer = Timer.scheduledTimer(withTimeInterval: num("dwell", 0.9), repeats: false) { [weak self] _ in
            guard let self = self, self.corner(at: NSEvent.mouseLocation) == c else { return }
            self.host?.fire(triggerId: c)
        }
    }
}
