import Cocoa

/// Time-based triggers. Built-in triggers (top of the hour, midnight, noon, sunrise, sunset) plus ten
/// user-written schedules, e.g. "weekdays 8:30", "every 30 min 9:00-17:00", "sunset -30m", "monthly 1 9:00".
public final class SchedulerPlugin: NSObject, ExternalTriggerPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.scheduler" }
    public var name: String { "Scheduler" }
    public var summary: String { "Run actions at times you choose" }
    public var version: String { "1.0.0" }
    public var author: String { "MouseGestures" }
    public var icon: String { "calendar.badge.clock" }

    static let slotCount = 10
    private static let builtins: [(id: String, name: String, summary: String, rule: String)] = [
        ("hourly", "Top of every hour", "Every hour on the hour", "every 1h"),
        ("midnight", "Midnight", "Start of each day", "0:00"),
        ("noon", "Noon", "12:00 every day", "12:00"),
        ("sunrise", "Sunrise", "Needs your latitude and longitude in the settings", "sunrise"),
        ("sunset", "Sunset", "Needs your latitude and longitude in the settings", "sunset"),
    ]

    private var settings: PluginHost?
    private weak var host: ExternalTriggerHost?
    private var timer: Timer?
    private var lastCheck = Date()
    private var observers: [NSObjectProtocol] = []

    // MARK: triggers (read each time the gesture editor opens)

    public var triggers: [ExternalTriggerDefinition] {
        var t = Self.builtins.map { ExternalTriggerDefinition(id: $0.id, name: $0.name, summary: $0.summary) }
        for n in 1...Self.slotCount {
            let rule = (settings?.string("slot\(n)") ?? "").trimmingCharacters(in: .whitespaces)
            guard !rule.isEmpty else { continue }
            let label = (settings?.string("slot\(n)Name") ?? "").trimmingCharacters(in: .whitespaces)
            let valid = TimeLogic.parseRule(rule) != nil
            t.append(ExternalTriggerDefinition(id: "slot\(n)", name: label.isEmpty ? rule : "\(label) (\(rule))",
                                               summary: valid ? "Schedule \(n)" : "Schedule \(n) — not understood, check its settings"))
        }
        return t
    }

    // MARK: settings

    public var settingsFields: [PluginSettingField] {
        var f: [PluginSettingField] = [
            PluginSettingField(key: "help", title: "How to write a schedule", kind: .info, help:
                "8:30  ·  weekdays 7pm  ·  mon,wed,fri noon  ·  sat,sun 22:00\nevery 30 min  ·  every 2h  ·  weekdays every 15 min 9:00-17:00\nsunrise  ·  sunset -30m  ·  sunrise +1h\nmonthly 1 9:00  ·  2026-12-25 08:00 (once)"),
            PluginSettingField(key: "latitude", title: "Latitude", kind: .text(placeholder: "40.7128"), help: "Only for sunrise / sunset. Negative = south."),
            PluginSettingField(key: "longitude", title: "Longitude", kind: .text(placeholder: "-74.0060"), help: "Negative = west."),
            PluginSettingField(key: "grace", title: "Catch up after sleep", kind: .number(min: 0, max: 120, step: 5, unit: "min"),
                               defaultValue: AnyCodable(5), help: "If the Mac was asleep at the scheduled time, still run it when it wakes up within this many minutes. 0 = never."),
        ]
        for n in 1...Self.slotCount {
            f.append(PluginSettingField(key: "slot\(n)", title: "Schedule \(n)", kind: .text(placeholder: "e.g. weekdays 8:30"), help: n == 1 ? "Leave blank to disable." : ""))
            f.append(PluginSettingField(key: "slot\(n)Name", title: "   Name", kind: .text(placeholder: "optional")))
        }
        return f
    }
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }
    public func settingChanged(key: String, value: Any?) { lastCheck = Date() }

    public var hasCustomSettingsView: Bool { true }
    public func makeSettingsView() -> NSView? { SchedulePanel(plugin: self) }

    // MARK: running

    public func start(host: ExternalTriggerHost) throws {
        self.host = host
        lastCheck = Date()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // a wake means the timer was frozen: check straight away so missed schedules can catch up
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.check()
        })
        host.log("Scheduler started")
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers.removeAll()
        host = nil
    }

    fileprivate var coordinates: (Double, Double)? {
        guard let la = Double((settings?.string("latitude") ?? "").trimmingCharacters(in: .whitespaces)),
              let lo = Double((settings?.string("longitude") ?? "").trimmingCharacters(in: .whitespaces)),
              abs(la) <= 90, abs(lo) <= 180 else { return nil }
        return (la, lo)
    }

    fileprivate func rule(for id: String) -> TimeLogic.Rule? {
        if let b = Self.builtins.first(where: { $0.id == id }) { return TimeLogic.parseRule(b.rule) }
        guard id.hasPrefix("slot"), let n = Int(id.dropFirst(4)) else { return nil }
        return TimeLogic.parseRule(settings?.string("slot\(n)") ?? "")
    }

    fileprivate var activeIds: [String] {
        Self.builtins.map { $0.id } + (1...Self.slotCount).map { "slot\($0)" }.filter { !(settings?.string($0) ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func check() {
        let now = Date()
        let from = lastCheck
        lastCheck = now
        let grace = (settings?.number("grace", default: 5) ?? 5) * 60
        let loc = coordinates
        for id in activeIds {
            guard let rule = rule(for: id) else { continue }
            // the latest occurrence in (from, now]
            var occurrence: Date?
            var cursor = from
            var guardCount = 0
            while let n = TimeLogic.next(rule, after: cursor, lat: loc?.0, lon: loc?.1), n <= now, guardCount < 50 { occurrence = n; cursor = n; guardCount += 1 }
            guard let when = occurrence else { continue }
            // a scheduled time that passed long ago (the Mac slept through it) is skipped
            if now.timeIntervalSince(when) > max(grace, 15) { host?.log("Skipped \(id): \(Int(now.timeIntervalSince(when)))s late"); continue }
            host?.log("Fired \(id)")
            host?.fire(triggerId: id)
        }
    }

    /// For the settings panel: when does this trigger next run?
    fileprivate func nextRun(_ id: String) -> Date? {
        guard let rule = rule(for: id) else { return nil }
        let loc = coordinates
        return TimeLogic.next(rule, after: Date(), lat: loc?.0, lon: loc?.1)
    }
    fileprivate func ruleText(_ n: Int) -> String { (settings?.string("slot\(n)") ?? "").trimmingCharacters(in: .whitespaces) }
    fileprivate func describe(_ id: String) -> String? { rule(for: id).map { TimeLogic.describe($0) } }
}

/// "Next runs" list shown in the settings sheet, with a warning for schedules that can't be read.
private final class SchedulePanel: NSView {
    private weak var plugin: SchedulerPlugin?
    private let body = NSTextField(wrappingLabelWithString: "")
    private var tick: Timer?

    init(plugin: SchedulerPlugin) {
        self.plugin = plugin
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 190))
        let title = NSTextField(labelWithString: "Next runs"); title.font = .systemFont(ofSize: 13, weight: .medium)
        body.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        body.maximumNumberOfLines = 0
        let stack = NSStackView(views: [title, body]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        refresh()
        tick = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self = self, self.window != nil || self.superview == nil else { t.invalidate(); return }
            self.refresh()
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { tick?.invalidate() }

    private func refresh() {
        guard let p = plugin else { return }
        var lines: [String] = []
        for id in p.activeIds {
            let isSlot = id.hasPrefix("slot")
            if isSlot, p.describe(id) == nil { lines.append("⚠️ \(id.replacingOccurrences(of: "slot", with: "Schedule ")): can't read “\(p.ruleText(Int(id.dropFirst(4)) ?? 0))”"); continue }
            if !isSlot, id == "sunrise" || id == "sunset", p.coordinates == nil { lines.append("\(id.capitalized): set latitude and longitude"); continue }
            let label = isSlot ? "Schedule " + id.dropFirst(4) : id.capitalized
            lines.append("\(label): " + (p.nextRun(id).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "never"))
        }
        let text = lines.joined(separator: "\n")
        if body.stringValue != text { body.stringValue = text }
    }
}
