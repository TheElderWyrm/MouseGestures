import Cocoa

/// Timers, Pomodoro, alarms and a stopwatch. State lives on the main thread, is saved to the plugin's
/// data folder after every change, and is resumed by the background service after a restart.
public final class TimersPlugin: NSObject, GestureActionPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.timers" }
    public var name: String { "Timers & Alarms" }
    public override var description: String { "Timers, Pomodoro, alarms, stopwatch and a spoken clock" }
    public var version: String { "1.0.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .productivity }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "timer", accessibilityDescription: nil) }

    // MARK: model

    struct Phase: Codable { var label: String; var seconds: TimeInterval }
    struct Item: Codable {
        var id: String
        var kind: String                 // "timer" | "alarm"
        var label: String
        var fire: Date
        var clock: [Int]?                // [hour, minute] for alarms
        var days: [Int]?                 // repeat days for alarms; nil = once
        var then: String?                // action identifier to run when it goes off
        var thenParams: String?
        var queue: [Phase] = []          // upcoming Pomodoro phases
    }
    struct State: Codable {
        var items: [Item] = []
        var swStart: Date?               // stopwatch running since
        var swAccum: TimeInterval = 0    // time banked while stopped
        var laps: [TimeInterval] = []
        var lastFired: String?
    }

    private var state = State()
    private var host: PluginHost?
    private var ticker: Timer?
    private var serviceRunning = false

    // MARK: actions

    private static func param(_ key: String, _ name: String, _ type: ParameterType, _ desc: String, def: Any? = nil,
                              min: Double? = nil, max: Double? = nil) -> ParameterDefinition {
        ParameterDefinition(key: key, name: name, type: type, defaultValue: def.map { AnyCodable($0) }, description: desc,
                            validation: (min != nil || max != nil) ? ValidationRule(minValue: min, maxValue: max) : nil)
    }
    private static let thenParams = [
        param("then", "Then run action", .actionId, "Optional: another action to run when it goes off"),
        param("thenParameters", "Action parameters", .string, "key=value,key=value for that action"),
    ]
    private static func choice(_ key: String, _ name: String, _ items: [(String, String)], _ def: String) -> ParameterDefinition {
        ParameterDefinition(key: key, name: name, type: .selection, defaultValue: AnyCodable(def), description: name,
                            validation: ValidationRule(allowedValues: items.map { AnyCodable($0.0) }),
                            displayValues: Dictionary(uniqueKeysWithValues: items))
    }

    public var providedActions: [PluginAction] {[
        PluginAction(id: "start_timer", name: "Start Timer", description: "Count down, then notify (and optionally run an action)",
                     supportedParameters: [Self.param("minutes", "Minutes", .number, "Length (blank = the default in settings)", min: 0.05, max: 1440),
                                           Self.param("label", "Label", .string, "Shown when time is up")] + Self.thenParams, icon: "timer"),
        PluginAction(id: "start_pomodoro", name: "Start Pomodoro", description: "Work / break cycles with a notification at each switch",
                     supportedParameters: [Self.param("work", "Work minutes", .number, "Focus length", def: 25, min: 1, max: 180),
                                           Self.param("shortBreak", "Break minutes", .number, "Short break length", def: 5, min: 1, max: 60),
                                           Self.param("longBreak", "Long break minutes", .number, "Break after the last round", def: 15, min: 1, max: 120),
                                           Self.param("rounds", "Rounds", .number, "Work sessions before the long break", def: 4, min: 1, max: 12)], icon: "brain.head.profile"),
        PluginAction(id: "set_alarm", name: "Set Alarm", description: "Ring at a clock time (7:30, 7pm, 19:30)", requiresParameters: true,
                     supportedParameters: [Self.param("time", "Time", .string, "7:30, 7pm, 19:30, noon…"),
                                           Self.param("label", "Label", .string, "Shown when it rings"),
                                           Self.choice("repeat", "Repeat", [("once", "Once"), ("daily", "Every day"), ("weekdays", "Weekdays"), ("weekends", "Weekends")], "once")] + Self.thenParams,
                     icon: "alarm"),
        PluginAction(id: "add_time", name: "Add Time to Timer", description: "Extend the next timer to ring (snooze it)",
                     supportedParameters: [Self.param("minutes", "Minutes", .number, "How much to add", def: 5, min: 1, max: 240)], icon: "plus.circle"),
        PluginAction(id: "snooze", name: "Snooze Last Alarm", description: "Start a short timer with the label of whatever rang last",
                     supportedParameters: [Self.param("minutes", "Minutes", .number, "Snooze length", def: 10, min: 1, max: 120)], icon: "zzz"),
        PluginAction(id: "show_timers", name: "Show Timers", description: "Notify what's running and when it rings", icon: "list.bullet.clipboard"),
        PluginAction(id: "cancel_next", name: "Cancel Next Timer", description: "Cancel the timer or alarm that rings next", icon: "xmark.circle"),
        PluginAction(id: "cancel_all", name: "Cancel All Timers", description: "Cancel every timer, alarm and Pomodoro", icon: "xmark.circle.fill"),
        PluginAction(id: "stopwatch", name: "Stopwatch", description: "Start/stop, lap, reset or show the stopwatch",
                     supportedParameters: [Self.choice("operation", "Operation", [("toggle", "Start / stop"), ("lap", "Lap"), ("reset", "Reset"), ("show", "Show time")], "toggle")], icon: "stopwatch"),
        PluginAction(id: "announce_time", name: "Speak the Time", description: "Say the current time out loud", icon: "speaker.wave.2"),
    ]}

    public func initialize(context: PluginContext) throws {}
    public func cleanup() {}

    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        if action.id == "set_alarm" {
            guard TimeLogic.parseClock(parameters.string(for: "time") ?? "") != nil else { return .invalid(error: "Enter a time like 7:30, 7pm or 19:30") }
        }
        return .valid
    }

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        let defMin = host?.number("defaultMinutes", default: 25) ?? 25
        func num(_ k: String, _ d: Double) -> Double { parameters.number(for: k) ?? d }
        let then = parameters.string(for: "then").flatMap { $0.isEmpty ? nil : $0 }
        let thenParams = parameters.string(for: "thenParameters")

        switch action.id {
        case "start_timer":
            let minutes = min(1440, max(0.05, num("minutes", defMin)))
            let label = parameters.string(for: "label").flatMap { $0.isEmpty ? nil : $0 } ?? "Timer"
            onMain { self.add(Item(id: UUID().uuidString, kind: "timer", label: label, fire: Date().addingTimeInterval(minutes * 60), then: then, thenParams: thenParams)) }
            context.showNotification(title: "\(label) started", message: TimeLogic.formatDuration(minutes * 60), style: .info)
        case "start_pomodoro":
            let work = num("work", 25) * 60, short = num("shortBreak", 5) * 60, long = num("longBreak", 15) * 60
            let rounds = max(1, Int(num("rounds", 4)))
            var phases: [Phase] = []
            for r in 1...rounds {
                phases.append(Phase(label: "Focus \(r)/\(rounds)", seconds: work))
                phases.append(Phase(label: r == rounds ? "Long break" : "Break", seconds: r == rounds ? long : short))
            }
            let first = phases.removeFirst()
            onMain { self.add(Item(id: UUID().uuidString, kind: "timer", label: first.label, fire: Date().addingTimeInterval(first.seconds), queue: phases)) }
            context.showNotification(title: "Pomodoro started", message: "\(first.label) — \(TimeLogic.formatDuration(first.seconds))", style: .info)
        case "set_alarm":
            guard let c = TimeLogic.parseClock(parameters.string(for: "time") ?? "") else { throw PluginError.invalidParameters("Unrecognised time") }
            let rep = parameters.string(for: "repeat") ?? "once"
            let days: Set<Int>? = rep == "daily" ? TimeLogic.allDays : rep == "weekdays" ? [2, 3, 4, 5, 6] : rep == "weekends" ? [1, 7] : nil
            guard let fire = TimeLogic.nextClock(hour: c.hour, minute: c.minute, days: days ?? TimeLogic.allDays, after: Date()) else { throw PluginError.executionFailed("No such time") }
            let label = parameters.string(for: "label").flatMap { $0.isEmpty ? nil : $0 } ?? "Alarm"
            onMain { self.add(Item(id: UUID().uuidString, kind: "alarm", label: label, fire: fire, clock: [c.hour, c.minute], days: days.map { Array($0).sorted() }, then: then, thenParams: thenParams)) }
            context.showNotification(title: "\(label) set", message: "Rings \(Self.whenText(fire))", style: .success)
        case "add_time":
            let m = num("minutes", 5)
            let ok: Bool = onMain {
                guard let i = self.nextIndex(kind: nil) else { return false }
                self.state.items[i].fire = max(self.state.items[i].fire, Date()).addingTimeInterval(m * 60); self.save(); return true
            }
            context.showNotification(title: "Timers", message: ok ? "Added \(Int(m)) min" : "Nothing is running", style: .info)
        case "snooze":
            let m = num("minutes", 10)
            let label: String = onMain { self.state.lastFired ?? "Timer" }
            onMain { self.add(Item(id: UUID().uuidString, kind: "timer", label: label, fire: Date().addingTimeInterval(m * 60))) }
            context.showNotification(title: "Snoozed", message: "\(label) again in \(Int(m)) min", style: .info)
        case "show_timers":
            let lines: [String] = onMain { self.summaryLines() }
            context.showNotification(title: "Timers", message: lines.isEmpty ? "Nothing is running" : lines.joined(separator: "\n"), style: .info)
        case "cancel_next":
            let label: String? = onMain {
                guard let i = self.nextIndex(kind: nil) else { return nil }
                let l = self.state.items.remove(at: i).label; self.save(); return l
            }
            context.showNotification(title: "Timers", message: label.map { "Cancelled \($0)" } ?? "Nothing to cancel", style: .info)
        case "cancel_all":
            let n: Int = onMain { let c = self.state.items.count; self.state.items.removeAll(); self.save(); return c }
            context.showNotification(title: "Timers", message: n == 0 ? "Nothing to cancel" : "Cancelled \(n)", style: .info)
        case "stopwatch":
            let op = parameters.string(for: "operation") ?? "toggle"
            let msg: String = onMain { self.stopwatch(op) }
            context.showNotification(title: "Stopwatch", message: msg, style: .info)
        case "announce_time":
            let df = DateFormatter(); df.dateStyle = .none; df.timeStyle = .short
            Self.speak("It's " + df.string(from: Date()))
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    // MARK: settings

    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "defaultMinutes", title: "Default timer length", kind: .number(min: 1, max: 240, step: 1, unit: "min"),
                           defaultValue: AnyCodable(25), help: "Used by “Start Timer” when a gesture doesn't set its own minutes."),
        PluginSettingField(key: "playSound", title: "Play a sound when time is up", kind: .toggle, defaultValue: AnyCodable(true)),
        PluginSettingField(key: "sound", title: "Sound",
                           kind: .choice(["Glass", "Hero", "Ping", "Submarine", "Funk", "Sosumi", "Basso"].map { PluginSettingChoice($0, $0) }), defaultValue: AnyCodable("Glass")),
        PluginSettingField(key: "speak", title: "Speak the label when time is up", kind: .toggle, defaultValue: AnyCodable(false)),
    ]}

    // MARK: service

    public var runsBackgroundService: Bool { true }
    public func pluginAttached(host: PluginHost) { self.host = host }
    public func pluginDetached() { ticker?.invalidate(); ticker = nil; host = nil }

    public func startService() throws {
        serviceRunning = true
        onMain {
            if let s = self.load() { self.state = s }
            // anything that came due while we weren't running
            let now = Date()
            for item in self.state.items where item.fire <= now { self.fireItem(item.id, late: true) }
            self.startTicker()
        }
    }

    public func stopService() {
        serviceRunning = false
        ticker?.invalidate(); ticker = nil
    }

    // MARK: core (main thread)

    private func onMain<T>(_ work: () -> T) -> T { Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work) }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        let now = Date()
        for item in state.items where item.fire <= now { fireItem(item.id, late: false) }
    }

    private func add(_ item: Item) {
        state.items.append(item); save()
        if ticker == nil { startTicker() }
    }

    private func nextIndex(kind: String?) -> Int? {
        state.items.indices.filter { kind == nil || state.items[$0].kind == kind }.min { state.items[$0].fire < state.items[$1].fire }
    }

    private func fireItem(_ id: String, late: Bool) {
        guard let i = state.items.firstIndex(where: { $0.id == id }) else { return }
        var item = state.items[i]
        state.lastFired = item.label
        let isAlarm = item.kind == "alarm"
        var message = isAlarm ? "Time's up" : "Time's up"
        if isAlarm { message = Self.whenText(item.fire, includeDay: false) }
        if late { message += " (missed while MouseGestures wasn't running)" }

        if !item.queue.isEmpty {                                    // Pomodoro: roll into the next phase
            let next = item.queue.removeFirst()
            message = "Next: \(next.label) — \(TimeLogic.formatDuration(next.seconds))"
            item.label = next.label; item.fire = Date().addingTimeInterval(next.seconds)
            state.items[i] = item
        } else if isAlarm, let days = item.days, let c = item.clock,
                  let nextFire = TimeLogic.nextClock(hour: c[0], minute: c[1], days: Set(days), after: Date()) {
            item.fire = nextFire; state.items[i] = item          // repeating alarm
        } else {
            state.items.remove(at: i)
        }
        save()
        ring(title: isAlarm ? "⏰ \(item.label)" : "\(state.lastFired ?? item.label) is done", message: message, speakText: state.lastFired ?? item.label)
        if !late, let a = item.then {
            do { try host?.executeAction(identifier: a, parameters: ActionParameters.parse(commaSeparated: item.thenParams ?? "")) }
            catch { host?.log("Follow-up action \(a) failed: \(error)") }
        }
    }

    private func ring(title: String, message: String, speakText: String) {
        if host?.bool("playSound", default: true) ?? true { NSSound(named: NSSound.Name(host?.string("sound", default: "Glass") ?? "Glass"))?.play() }
        host?.notify(title: title, message: message)
        if host?.bool("speak", default: false) ?? false { Self.speak(speakText) }
    }

    private func stopwatch(_ op: String) -> String {
        func elapsed() -> TimeInterval { state.swAccum + (state.swStart.map { Date().timeIntervalSince($0) } ?? 0) }
        switch op {
        case "reset": state = { var s = state; s.swStart = nil; s.swAccum = 0; s.laps = []; return s }(); save(); return "Reset"
        case "lap":
            guard state.swStart != nil else { return "Not running" }
            state.laps.append(elapsed()); save()
            return "Lap \(state.laps.count): \(Self.clock(elapsed()))"
        case "show": return (state.swStart == nil ? "Stopped at " : "Running: ") + Self.clock(elapsed())
        default:
            if let start = state.swStart { state.swAccum += Date().timeIntervalSince(start); state.swStart = nil; save(); return "Stopped at \(Self.clock(state.swAccum))" }
            state.swStart = Date(); save(); return state.swAccum > 0 ? "Resumed from \(Self.clock(state.swAccum))" : "Started"
        }
    }

    fileprivate func summaryLines() -> [String] {
        let now = Date()
        var lines = state.items.sorted { $0.fire < $1.fire }.map { "\($0.label): \($0.kind == "alarm" ? Self.whenText($0.fire) : "in " + TimeLogic.formatDuration($0.fire.timeIntervalSince(now)))" }
        if state.swStart != nil || state.swAccum > 0 { lines.append("Stopwatch: \(Self.clock(state.swAccum + (state.swStart.map { now.timeIntervalSince($0) } ?? 0)))") }
        return lines
    }

    fileprivate var items: [Item] { state.items.sorted { $0.fire < $1.fire } }
    fileprivate func cancel(id: String) { state.items.removeAll { $0.id == id }; save() }
    fileprivate func panelStart() {
        add(Item(id: UUID().uuidString, kind: "timer", label: "Timer", fire: Date().addingTimeInterval((host?.number("defaultMinutes", default: 25) ?? 25) * 60)))
    }

    static func whenText(_ d: Date, includeDay: Bool = true) -> String {
        let cal = Calendar.current
        let time = TimeLogic.clockString(d)
        guard includeDay else { return time }
        if cal.isDateInToday(d) { return "today at \(time)" }
        if cal.isDateInTomorrow(d) { return "tomorrow at \(time)" }
        let df = DateFormatter(); df.dateFormat = "EEEE"; return "\(df.string(from: d)) at \(time)"
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t); let cs = Int((t - Double(s)) * 100)
        return s >= 3600 ? String(format: "%d:%02d:%02d.%02d", s / 3600, (s % 3600) / 60, s % 60, cs) : String(format: "%d:%02d.%02d", s / 60, s % 60, cs)
    }

    static func speak(_ text: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = [text]
        try? p.run()
    }

    // MARK: persistence

    private var stateURL: URL? { host?.storageDirectory.appendingPathComponent("timers.json") }
    private func save() {
        guard let url = stateURL else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(state) { try? data.write(to: url, options: .atomic) }
    }
    private func load() -> State? {
        guard let url = stateURL, let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(State.self, from: data)
    }

    // MARK: UI

    public var hasCustomSettingsView: Bool { true }
    public func makeSettingsView() -> NSView? { TimersPanel(plugin: self) }
}

/// Live list of running timers and alarms in the plugin's settings sheet.
private final class TimersPanel: NSView {
    private weak var plugin: TimersPlugin?
    private let stack = NSStackView()
    private var tick: Timer?
    private var shown: [String] = []

    init(plugin: TimersPlugin) {
        self.plugin = plugin
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        rebuild()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self = self, self.window != nil || self.superview == nil else { t.invalidate(); return }
            self.rebuild()
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { tick?.invalidate() }

    private func rebuild() {
        guard let plugin = plugin else { return }
        let lines = plugin.summaryLines()
        let key = plugin.items.map { $0.id + $0.label } + lines
        guard key != shown else { return }
        shown = key
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let title = NSTextField(labelWithString: "Running now"); title.font = .systemFont(ofSize: 13, weight: .medium)
        stack.addArrangedSubview(title)
        if plugin.items.isEmpty { stack.addArrangedSubview(NSTextField(labelWithString: "No timers or alarms")) }
        let now = Date()
        for item in plugin.items {
            let text = item.kind == "alarm" ? TimersPlugin.whenText(item.fire) : "in " + TimeLogic.formatDuration(item.fire.timeIntervalSince(now))
            let label = NSTextField(labelWithString: "\(item.label) — \(text)")
            let b = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(item.id); b.controlSize = .small
            let row = NSStackView(views: [label, b]); row.spacing = 8
            stack.addArrangedSubview(row)
        }
        let start = NSButton(title: "Start default timer", target: self, action: #selector(startTapped))
        stack.addArrangedSubview(start)
    }

    @objc private func cancelTapped(_ s: NSButton) { if let id = s.identifier?.rawValue { plugin?.cancel(id: id); shown = []; rebuild() } }
    @objc private func startTapped() { plugin?.panelStart(); shown = []; rebuild() }
}
