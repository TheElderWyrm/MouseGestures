import Cocoa
import SwiftUI
import MouseGestures

/// Time-based triggers. A set of ready-made schedules (top of the hour, mornings, sunrise…) that you can edit or
/// delete, any number of your own built in the plugin's settings, and a "Custom schedule" that is configured right
/// in the gesture: specific dates, days of the week, every N days or weeks, monthly (a date, the last day, the Nth
/// weekday), yearly, intervals, or sunrise / sunset.
@objc(SchedulerPlugin)
public final class SchedulerPlugin: NSObject, ExternalTriggerPlugin, ExternalTriggerParameterized, ExternalTriggerBindingAware, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.scheduler" }
    public var name: String { "Scheduler" }
    public var summary: String { "Run actions at times you choose" }
    public var version: String { "1.2.0" }
    public var author: String { "MouseGestures" }
    public var icon: String { "calendar.badge.clock" }

    static let legacySlotCount = 10          // schedules written as text in versions before 1.1
    /// Ready-made schedules, added once on first run and then yours to edit or delete. The first five keep the ids of
    /// the triggers earlier versions had built in, so gestures already using them keep working.
    private static let presets: [ScheduleEvent] = {
        func p(_ id: String, _ name: String, _ build: (inout ScheduleSpec) -> Void) -> ScheduleEvent {
            var spec = ScheduleSpec(); build(&spec); return ScheduleEvent(id: id, name: name, spec: spec)
        }
        let weekdays = [2, 3, 4, 5, 6]
        return [
            p("hourly", "Top of every hour") { $0.kind = .interval; $0.intervalMinutes = 60 },
            p("midnight", "Midnight") { $0.hour = 0 },
            p("noon", "Noon") { $0.hour = 12 },
            p("sunrise", "Sunrise") { $0.kind = .solar; $0.sunrise = true },
            p("sunset", "Sunset") { $0.kind = .solar; $0.sunrise = false },
            p("preset-morning", "Every morning (8:00)") { $0.hour = 8 },
            p("preset-weekday-morning", "Weekday mornings (8:30)") { $0.days = weekdays; $0.hour = 8; $0.minute = 30 },
            p("preset-weekday-start", "Start of the work day (9:00, weekdays)") { $0.days = weekdays; $0.hour = 9 },
            p("preset-weekday-end", "End of the work day (5:00 pm, weekdays)") { $0.days = weekdays; $0.hour = 17 },
            p("preset-evening", "Every evening (8:00 pm)") { $0.hour = 20 },
            p("preset-bedtime", "Bedtime (10:30 pm)") { $0.hour = 22; $0.minute = 30 },
            p("preset-weekend-morning", "Weekend mornings (10:00)") { $0.days = [1, 7]; $0.hour = 10 },
            p("preset-monday", "Monday mornings (9:00)") { $0.days = [2]; $0.hour = 9 },
            p("preset-friday", "Friday afternoons (4:00 pm)") { $0.days = [6]; $0.hour = 16 },
            p("preset-every-15", "Every 15 minutes") { $0.kind = .interval; $0.intervalMinutes = 15 },
            p("preset-every-30", "Every 30 minutes") { $0.kind = .interval; $0.intervalMinutes = 30 },
            p("preset-work-hours", "Every 15 minutes, work hours (weekdays 9–5)") {
                $0.kind = .interval; $0.intervalMinutes = 15; $0.days = weekdays; $0.windowOn = true
            },
            p("preset-month-start", "First of the month (9:00)") { $0.kind = .monthlyDay; $0.monthDay = 1 },
            p("preset-month-end", "Last day of the month (5:00 pm)") { $0.kind = .monthlyDay; $0.monthDay = 0; $0.hour = 17 },
            p("preset-first-monday", "First Monday of the month (9:00)") { $0.kind = .monthlyNth; $0.nth = 1; $0.weekday = 2 },
            p("preset-new-year", "New Year's Day (midnight)") {
                $0.kind = .yearly; $0.hour = 0
                $0.date = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date()
            },
        ]
    }()
    private var seeding = false

    private var settings: PluginHost?
    private weak var host: ExternalTriggerHost?
    private var timer: Timer?
    private var lastCheck = Date()
    private var observers: [NSObjectProtocol] = []

    // MARK: schedules

    /// Legacy text slots first (their ids are bound in existing gestures), then the schedules built in the editor.
    fileprivate func allEvents() -> [ScheduleEvent] {
        seedPresetsIfNeeded()
        var out: [ScheduleEvent] = []
        for n in 1...Self.legacySlotCount {
            let rule = (settings?.string("slot\(n)") ?? "").trimmingCharacters(in: .whitespaces)
            guard !rule.isEmpty else { continue }
            var spec = ScheduleSpec(); spec.kind = .custom; spec.text = rule
            out.append(ScheduleEvent(id: "slot\(n)", name: (settings?.string("slot\(n)Name") ?? "").trimmingCharacters(in: .whitespaces), spec: spec))
        }
        if let json = settings?.string("events"), let data = json.data(using: .utf8),
           let list = try? JSONDecoder().decode([ScheduleEvent].self, from: data) { out += list }
        return out
    }

    /// First run only (so deleting a preset sticks): add the ready-made schedules after anything already saved.
    private func seedPresetsIfNeeded() {
        guard !seeding, let settings = settings, settings.setting("presetsSeeded") == nil else { return }
        seeding = true; defer { seeding = false }
        var saved: [ScheduleEvent] = []
        if let data = settings.string("events").data(using: .utf8),
           let list = try? JSONDecoder().decode([ScheduleEvent].self, from: data) { saved = list }
        let have = Set(saved.map { $0.id })
        store(Self.presets.filter { !have.contains($0.id) } + saved)
        settings.setSetting("presetsSeeded", to: true)
    }

    fileprivate func save(_ event: ScheduleEvent) {
        if event.id.hasPrefix("slot"), let n = Int(event.id.dropFirst(4)) {      // legacy text schedule
            settings?.setSetting("slot\(n)", to: event.spec.kind == .custom ? event.spec.text : event.spec.rule())
            settings?.setSetting("slot\(n)Name", to: event.name)
            return
        }
        var list = allEvents().filter { !$0.id.hasPrefix("slot") }
        if let i = list.firstIndex(where: { $0.id == event.id }) { list[i] = event } else { list.append(event) }
        store(list)
    }

    fileprivate func delete(_ id: String) {
        if id.hasPrefix("slot"), let n = Int(id.dropFirst(4)) {
            settings?.setSetting("slot\(n)", to: ""); settings?.setSetting("slot\(n)Name", to: ""); return
        }
        store(allEvents().filter { !$0.id.hasPrefix("slot") && $0.id != id })
    }

    private func store(_ list: [ScheduleEvent]) {
        if let data = try? JSONEncoder().encode(list), let json = String(data: data, encoding: .utf8) { settings?.setSetting("events", to: json) }
    }

    // MARK: triggers (read each time the gesture editor opens)

    public var triggers: [ExternalTriggerDefinition] {
        var t = [ExternalTriggerDefinition(id: Self.customId, name: "Custom schedule…", summary: "Set the days and times right here")]
        for e in allEvents() {
            let rule = TimeLogic.parseRule(e.spec.rule())
            let what = rule.map { TimeLogic.describe($0) } ?? "not understood, check its settings"
            t.append(ExternalTriggerDefinition(id: e.id, name: e.name.isEmpty ? what : "\(e.name) (\(what))", summary: what))
        }
        return t
    }

    // MARK: settings

    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "latitude", title: "Latitude", kind: .text(placeholder: "40.7128"), help: "Only for sunrise / sunset. Negative = south."),
        PluginSettingField(key: "longitude", title: "Longitude", kind: .text(placeholder: "-74.0060"), help: "Negative = west."),
        PluginSettingField(key: "grace", title: "Catch up after sleep", kind: .number(min: 0, max: 120, step: 5, unit: "min"),
                           defaultValue: AnyCodable(5), help: "If the Mac was asleep at the scheduled time, still run it when it wakes up within this many minutes. 0 = never."),
    ]}
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }
    public func settingChanged(key: String, value: Any?) { lastCheck = Date() }

    public var hasCustomSettingsView: Bool { true }
    public func makeSettingsView() -> NSView? {
        let hosting = NSHostingView(rootView: SchedulerPanelView(plugin: self))
        hosting.sizingOptions = [.intrinsicContentSize]
        return hosting
    }

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
        allEvents().first { $0.id == id }.flatMap { TimeLogic.parseRule($0.spec.rule()) }
    }

    // MARK: custom schedule (configured per gesture)

    static let customId = "custom"
    private var customBindings: [ExternalTriggerBinding] = []

    public func bindingsChanged(_ bindings: [ExternalTriggerBinding]) {
        customBindings = bindings.filter { $0.triggerId == Self.customId }
        lastCheck = Date()
    }

    public func parameters(forTrigger id: String) -> [ParameterDefinition] {
        id == Self.customId ? Self.customParameters : []
    }

    private static func choice(_ key: String, _ name: String, _ items: [(String, String)], _ def: String, when: ParameterVisibilityRule? = nil) -> ParameterDefinition {
        ParameterDefinition(key: key, name: name, type: .selection, defaultValue: AnyCodable(def), description: "",
                            validation: ValidationRule(allowedValues: items.map { AnyCodable($0.0) }),
                            visibleWhen: when, displayValues: Dictionary(uniqueKeysWithValues: items))
    }

    private static let customParameters: [ParameterDefinition] = {
        func only(_ kinds: [ScheduleSpec.Kind]) -> ParameterVisibilityRule { ParameterVisibilityRule(key: "repeat", anyOf: kinds.map { $0.rawValue }) }
        let weekdayNames = [("sun", "Sunday"), ("mon", "Monday"), ("tue", "Tuesday"), ("wed", "Wednesday"), ("thu", "Thursday"), ("fri", "Friday"), ("sat", "Saturday")]
        return [
            choice("repeat", "Repeats", ScheduleSpec.Kind.allCases.map { ($0.rawValue, $0.label) }, ScheduleSpec.Kind.weekly.rawValue),
            ParameterDefinition(key: "days", name: "On these days", type: .weekdays, description: "", visibleWhen: only([.weekly, .interval, .intervalWindow, .solar])),
            ParameterDefinition(key: "time", name: "At", type: .time, defaultValue: AnyCodable("9:00"), description: "",
                                visibleWhen: only([.weekly, .once, .everyN, .monthlyDay, .monthlyNth, .yearly])),
            ParameterDefinition(key: "date", name: "Date", type: .date, description: "Once: the day. Every N: the start. Yearly: month and day.",
                                visibleWhen: only([.once, .everyN, .yearly])),
            ParameterDefinition(key: "every", name: "Every", type: .number, defaultValue: AnyCodable(2), description: "",
                                validation: ValidationRule(minValue: 1, maxValue: 52), visibleWhen: only([.everyN])),
            choice("unit", "", [("weeks", "weeks"), ("days", "days")], "weeks", when: only([.everyN])),
            choice("monthDay", "Day of the month", [("last", "Last day")] + (1...31).map { ("\($0)", "Day \($0)") }, "1", when: only([.monthlyDay])),
            choice("nth", "Which", [("1", "First"), ("2", "Second"), ("3", "Third"), ("4", "Fourth"), ("last", "Last")], "1", when: only([.monthlyNth])),
            choice("weekday", "Weekday", weekdayNames, "mon", when: only([.monthlyNth])),
            ParameterDefinition(key: "minutes", name: "Every", type: .number, defaultValue: AnyCodable(30), description: "",
                                validation: ValidationRule(minValue: 1, maxValue: 720), visibleWhen: only([.interval, .intervalWindow]), suffix: "min"),
            ParameterDefinition(key: "from", name: "From", type: .time, defaultValue: AnyCodable("9:00"), description: "", visibleWhen: only([.intervalWindow])),
            ParameterDefinition(key: "to", name: "Until", type: .time, defaultValue: AnyCodable("17:00"), description: "", visibleWhen: only([.intervalWindow])),
            choice("sun", "Event", [("sunrise", "Sunrise"), ("sunset", "Sunset")], "sunrise", when: only([.solar])),
            ParameterDefinition(key: "offset", name: "Offset", type: .number, defaultValue: AnyCodable(0),
                                description: "Minutes after (negative = before). Needs your latitude and longitude in the plugin's settings.",
                                validation: ValidationRule(minValue: -180, maxValue: 180), visibleWhen: only([.solar]), suffix: "min"),
            ParameterDefinition(key: "dates", name: "Dates", type: .string,
                                description: "2026-12-25 8:00; 2027-01-01 9:00", visibleWhen: only([.dates])),
            ParameterDefinition(key: "rule", name: "Rule", type: .string,
                                description: "e.g. weekdays 8:30", visibleWhen: only([.custom])),
        ]
    }()

    private func check() {
        let now = Date()
        let from = lastCheck
        lastCheck = now
        let grace = (settings?.number("grace", default: 5) ?? 5) * 60
        let loc = coordinates
        // decode the schedules once per tick, not once per schedule
        var schedules: [(id: String, rule: TimeLogic.Rule, binding: ExternalTriggerBinding?)] =
            allEvents().compactMap { e in TimeLogic.parseRule(e.spec.rule()).map { (e.id, $0, nil) } }
        for b in customBindings {
            if let r = TimeLogic.parseRule(ScheduleSpec(options: b.options).rule()) { schedules.append(("custom", r, b)) }
        }
        for (id, rule, binding) in schedules {
            // the latest occurrence in (from, now]
            var occurrence: Date?
            var cursor = from
            var guardCount = 0
            while let n = TimeLogic.next(rule, after: cursor, lat: loc?.0, lon: loc?.1), n <= now, guardCount < 50 { occurrence = n; cursor = n; guardCount += 1 }
            guard let when = occurrence else { continue }
            // a scheduled time that passed long ago (the Mac slept through it) is skipped
            if now.timeIntervalSince(when) > max(grace, 15) { host?.log("Skipped \(id): \(Int(now.timeIntervalSince(when)))s late"); continue }
            host?.log("Fired \(id)")
            if let binding = binding, let bindingHost = host as? ExternalTriggerBindingHost { bindingHost.fire(binding: binding) }
            else { host?.fire(triggerId: id) }
        }
    }

    /// For the settings panel: when does this trigger next run?
    fileprivate func nextRun(_ id: String) -> Date? {
        guard let rule = rule(for: id) else { return nil }
        let loc = coordinates
        return TimeLogic.next(rule, after: Date(), lat: loc?.0, lon: loc?.1)
    }
}

// MARK: - Schedule model

/// What the editor collects. `rule()` turns it into the text grammar `TimeLogic.parseRule` understands, so the
/// engine and the text form stay one thing. Weekdays use Foundation numbering (1 = Sunday).
struct ScheduleSpec: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case weekly, once, dates, everyN, monthlyDay, monthlyNth, yearly, interval, intervalWindow, solar, custom
        var label: String {
            switch self {
            case .weekly: return "Days of the week"
            case .once: return "Once, on a date"
            case .dates: return "Several specific dates"
            case .everyN: return "Every N days or weeks"
            case .monthlyDay: return "Monthly, on a date (the 15th, the last day…)"
            case .monthlyNth: return "Monthly, on the Nth weekday (2nd Tuesday…)"
            case .yearly: return "Yearly, on a date"
            case .interval: return "Every N minutes"
            case .intervalWindow: return "Every N minutes, between certain hours"
            case .solar: return "Sunrise or sunset"
            case .custom: return "Write the rule as text"
            }
        }
    }
    var kind: Kind = .weekly
    var hour = 9, minute = 0
    var days: [Int] = Array(1...7)
    var date = Date()
    var dates: [Date] = []
    var n = 2
    var weeks = true
    var monthDay = 1                  // 0 = the last day
    var nth = 1                       // 1…4, -1 = last
    var weekday = 2
    var intervalMinutes = 30
    var windowOn = false
    var windowStart = 9 * 60, windowEnd = 17 * 60
    var sunrise = true
    var offsetMinutes = 0
    var text = ""

    private static let names = ["", "sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    private var clock: String { String(format: "%d:%02d", hour, minute) }
    private func ymd(_ d: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
    private func moment(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return "\(ymd(d)) \(c.hour ?? 0):" + String(format: "%02d", c.minute ?? 0)
    }
    private var dayPrefix: String {
        let set = Set(days)
        if set.count == 7 || set.isEmpty { return "" }
        if set == [2, 3, 4, 5, 6] { return "weekdays " }
        if set == [1, 7] { return "weekends " }
        return set.sorted().map { Self.names[$0] }.joined(separator: ",") + " "
    }

    func rule() -> String {
        switch kind {
        case .weekly: return dayPrefix + clock
        case .once: return "\(ymd(date)) \(clock)"
        case .dates: return dates.isEmpty ? "" : "dates " + dates.sorted().map(moment).joined(separator: "; ")
        case .everyN: return "every \(n) \(weeks ? "weeks" : "days") from \(ymd(date)) \(clock)"
        case .monthlyDay: return monthDay == 0 ? "monthly last \(clock)" : "monthly \(monthDay) \(clock)"
        case .monthlyNth:
            let ord = nth == -1 ? "last" : ["1st", "2nd", "3rd", "4th"][max(0, min(3, nth - 1))]
            return "monthly \(ord) \(Self.names[weekday]) \(clock)"
        case .yearly:
            let c = Calendar.current.dateComponents([.month, .day], from: date)
            return "yearly \(c.month ?? 1)-\(c.day ?? 1) \(clock)"
        case .interval, .intervalWindow:
            let w = (windowOn || kind == .intervalWindow) ? String(format: " %d:%02d-%d:%02d", windowStart / 60, windowStart % 60, windowEnd / 60, windowEnd % 60) : ""
            return "\(dayPrefix)every \(intervalMinutes) min\(w)"
        case .solar:
            let off = offsetMinutes == 0 ? "" : (offsetMinutes > 0 ? " +\(offsetMinutes)m" : " -\(-offsetMinutes)m")
            return "\(dayPrefix)\(sunrise ? "sunrise" : "sunset")\(off)"
        case .custom: return text
        }
    }
}

extension ScheduleSpec {
    /// Builds a spec from the parameter form of the Scheduler's "Custom schedule" trigger (see `customParameters`).
    init(options o: [String: Any]) {
        self.init()
        func str(_ k: String) -> String? { o[k] as? String }
        func num(_ k: String) -> Double? { (o[k] as? NSNumber)?.doubleValue }
        func clock(_ k: String) -> (Int, Int)? {
            guard let p = str(k)?.split(separator: ":").compactMap({ Int($0) }), p.count == 2 else { return nil }
            return (p[0], p[1])
        }
        let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        kind = Kind(rawValue: str("repeat") ?? "") ?? .weekly
        if let (h, m) = clock("time") { hour = h; minute = m }
        if let list = str("days")?.split(separator: ","), !list.isEmpty {
            days = list.compactMap { names.firstIndex(of: String($0).trimmingCharacters(in: .whitespaces)).map { $0 + 1 } }
        }
        if let d = str("date") {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
            if let parsed = f.date(from: d) { date = parsed }
        }
        n = Int(num("every") ?? 2); weeks = str("unit") != "days"
        monthDay = str("monthDay") == "last" ? 0 : Int(str("monthDay") ?? "") ?? 1
        nth = str("nth") == "last" ? -1 : Int(str("nth") ?? "") ?? 1
        weekday = (names.firstIndex(of: str("weekday") ?? "mon") ?? 1) + 1
        intervalMinutes = Int(num("minutes") ?? 30)
        if let (h, m) = clock("from") { windowStart = h * 60 + m }
        if let (h, m) = clock("to") { windowEnd = h * 60 + m }
        sunrise = str("sun") != "sunset"
        offsetMinutes = Int(num("offset") ?? 0)
        dates = (str("dates") ?? "").split(separator: ";").compactMap { TimeLogic.parseMoment(String($0)) }
        text = str("rule") ?? ""
    }
}

struct ScheduleEvent: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var spec: ScheduleSpec
}

// MARK: - Settings panel

private struct SchedulerPanelView: View {
    let plugin: SchedulerPlugin
    @State private var events: [ScheduleEvent] = []
    @State private var editing: ScheduleEvent?
    @State private var isNew = false
    @State private var tick = Date()
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Schedules").font(.system(size: 13, weight: .medium))
                Spacer()
                Button {
                    var spec = ScheduleSpec(); spec.date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    editing = ScheduleEvent(id: "evt-" + UUID().uuidString.prefix(8).lowercased(), name: "", spec: spec); isNew = true
                } label: { Label("Add schedule", systemImage: "plus") }
                .disabled(editing != nil)
            }
            if events.isEmpty && editing == nil {
                Text("No schedules yet. Add one to run an action on certain days, dates, or times, then pick it as a Scheduler trigger when you create a gesture.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(events) { e in
                if editing?.id == e.id && !isNew { editor } else { row(e) }
            }
            if isNew, editing != nil { editor }
        }
        .padding(.vertical, 4)
        .onAppear { reload() }
        .onReceive(timer) { tick = $0 }
    }

    private func reload() { events = plugin.allEvents() }

    private func row(_ e: ScheduleEvent) -> some View {
        let _ = tick
        let rule = TimeLogic.parseRule(e.spec.rule())
        let next = plugin.nextRun(e.id)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name.isEmpty ? (rule.map { TimeLogic.describe($0) } ?? "Unreadable schedule") : e.name).font(.system(size: 12, weight: .medium))
                if !e.name.isEmpty, let r = rule { Text(TimeLogic.describe(r)).font(.caption).foregroundColor(.secondary) }
                Text(rule == nil ? "⚠️ Can't read “\(e.spec.rule())”"
                     : next.map { "Next: " + $0.formatted(date: .abbreviated, time: .shortened) } ?? (e.spec.kind == .solar ? "Set latitude and longitude above" : "Nothing left to run"))
                    .font(.caption).foregroundColor(rule == nil ? .red : .secondary)
            }
            Spacer()
            Button("Edit") { editing = e; isNew = false }.disabled(editing != nil)
            Button { plugin.delete(e.id); reload() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Delete. Gestures using it will stop firing.").disabled(editing != nil)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    @ViewBuilder private var editor: some View {
        if editing != nil {
            VStack(alignment: .leading, spacing: 10) {
                ScheduleEditor(event: Binding(get: { editing ?? ScheduleEvent(id: "", name: "", spec: ScheduleSpec()) }, set: { editing = $0 }),
                               hasLocation: plugin.coordinates != nil)
                HStack {
                    Spacer()
                    Button("Cancel") { editing = nil; isNew = false }
                    Button("Save") {
                        if let e = editing { plugin.save(e) }
                        editing = nil; isNew = false; reload()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(TimeLogic.parseRule(editing?.spec.rule() ?? "") == nil)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.5)))
        }
    }
}

private struct ScheduleEditor: View {
    @Binding var event: ScheduleEvent
    let hasLocation: Bool

    private var spec: Binding<ScheduleSpec> { $event.spec }
    private let weekdayNames = [(1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat")]
    private let monthNames = Calendar.current.monthSymbols

    private var timeBinding: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: event.spec.hour, minute: event.spec.minute, second: 0, of: Date()) ?? Date() },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); event.spec.hour = c.hour ?? 0; event.spec.minute = c.minute ?? 0 })
    }
    private func minutesBinding(_ kp: WritableKeyPath<ScheduleSpec, Int>) -> Binding<Date> {
        Binding(get: { let m = event.spec[keyPath: kp]; return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date() },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); event.spec[keyPath: kp] = (c.hour ?? 0) * 60 + (c.minute ?? 0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name (optional)", text: $event.name).textFieldStyle(.roundedBorder)
            Picker("Repeats", selection: spec.kind) { ForEach(ScheduleSpec.Kind.allCases.filter { $0 != .intervalWindow }, id: \.self) { Text($0.label).tag($0) } }
            switch event.spec.kind {
            case .weekly:
                weekdayPicker
                timeRow
            case .once:
                DatePicker("Date", selection: spec.date, displayedComponents: .date)
                timeRow
            case .dates:
                ForEach(event.spec.dates.indices, id: \.self) { i in
                    HStack {
                        DatePicker("", selection: Binding(get: { event.spec.dates[i] }, set: { event.spec.dates[i] = $0 }))
                            .labelsHidden()
                        Button { event.spec.dates.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button {
                    let base = Calendar.current.date(byAdding: .day, value: 1, to: event.spec.dates.max() ?? Date()) ?? Date()
                    event.spec.dates.append(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base)
                } label: { Label("Add a date", systemImage: "plus.circle") }.buttonStyle(.borderless)
            case .everyN:
                HStack {
                    Stepper("Every \(event.spec.n)", value: spec.n, in: 1...52)
                    Picker("", selection: spec.weeks) { Text("weeks").tag(true); Text("days").tag(false) }.labelsHidden().fixedSize()
                }
                DatePicker("Starting", selection: spec.date, displayedComponents: .date)
                timeRow
            case .monthlyDay:
                Picker("Day", selection: spec.monthDay) {
                    Text("Last day of the month").tag(0)
                    ForEach(1...31, id: \.self) { Text("Day \($0)").tag($0) }
                }
                if event.spec.monthDay > 28 { Text("Months without that day are skipped.").font(.caption).foregroundColor(.secondary) }
                timeRow
            case .monthlyNth:
                HStack {
                    Picker("", selection: spec.nth) {
                        Text("First").tag(1); Text("Second").tag(2); Text("Third").tag(3); Text("Fourth").tag(4); Text("Last").tag(-1)
                    }.labelsHidden().fixedSize()
                    Picker("", selection: spec.weekday) { ForEach(weekdayNames, id: \.0) { Text(Calendar.current.weekdaySymbols[$0.0 - 1]).tag($0.0) } }
                        .labelsHidden().fixedSize()
                    Text("of every month")
                }
                timeRow
            case .yearly:
                DatePicker("Date", selection: spec.date, displayedComponents: .date)
                Text("Repeats every year on \(monthNames[Calendar.current.component(.month, from: event.spec.date) - 1]) \(Calendar.current.component(.day, from: event.spec.date)). Pick the month and day; the year is ignored.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                timeRow
            case .interval, .intervalWindow:
                Stepper("Every \(event.spec.intervalMinutes) minutes", value: spec.intervalMinutes, in: 1...720, step: 5)
                Toggle("Only between certain hours", isOn: spec.windowOn)
                if event.spec.windowOn {
                    HStack {
                        DatePicker("From", selection: minutesBinding(\.windowStart), displayedComponents: .hourAndMinute)
                        DatePicker("to", selection: minutesBinding(\.windowEnd), displayedComponents: .hourAndMinute)
                    }
                }
                weekdayPicker
            case .solar:
                Picker("", selection: spec.sunrise) { Text("Sunrise").tag(true); Text("Sunset").tag(false) }.pickerStyle(.segmented).labelsHidden()
                Stepper(event.spec.offsetMinutes == 0 ? "At the time itself"
                        : "\(abs(event.spec.offsetMinutes)) minutes \(event.spec.offsetMinutes > 0 ? "after" : "before")",
                        value: spec.offsetMinutes, in: -180...180, step: 5)
                if !hasLocation { Text("⚠️ Set your latitude and longitude above first.").font(.caption).foregroundColor(.orange) }
                weekdayPicker
            case .custom:
                TextField("e.g. weekdays 8:30 · monthly 2nd tue 9:00", text: spec.text).textFieldStyle(.roundedBorder)
                Text("8:30 · weekdays 7pm · mon,wed,fri noon · every 30 min 9:00-17:00 · sunset -30m · monthly last fri 17:00 · yearly 12-25 9:00 · every 2 weeks from 2026-10-12 9:00 · dates 2026-12-25 8:00; 2027-01-01 9:00")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            preview
        }
    }

    private var timeRow: some View { DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute) }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(weekdayNames, id: \.0) { d, label in
                    let on = event.spec.days.contains(d)
                    Button(label) {
                        if on { event.spec.days.removeAll { $0 == d } } else { event.spec.days.append(d) }
                    }
                    .buttonStyle(.bordered).tint(on ? .accentColor : .gray).controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                Button("Every day") { event.spec.days = Array(1...7) }
                Button("Weekdays") { event.spec.days = [2, 3, 4, 5, 6] }
                Button("Weekends") { event.spec.days = [1, 7] }
            }
            .buttonStyle(.link).font(.caption)
            if event.spec.days.isEmpty { Text("No days selected: it will run every day.").font(.caption).foregroundColor(.secondary) }
        }
    }

    /// What this will do, and the next few times, computed by the same engine that runs it.
    @ViewBuilder private var preview: some View {
        let rule = TimeLogic.parseRule(event.spec.rule())
        VStack(alignment: .leading, spacing: 2) {
            if let rule = rule {
                Text(TimeLogic.describe(rule)).font(.caption.weight(.medium))
                let runs = upcoming(rule)
                Text(runs.isEmpty ? (event.spec.kind == .solar && !hasLocation ? "Needs your location" : "Nothing left to run")
                     : "Next: " + runs.map { $0.formatted(date: .abbreviated, time: .shortened) }.joined(separator: "  ·  "))
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(event.spec.kind == .dates ? "Add at least one date." : "This schedule can't be read yet.").font(.caption).foregroundColor(.red)
            }
        }
    }

    private func upcoming(_ rule: TimeLogic.Rule) -> [Date] {
        var out: [Date] = [], cursor = Date()
        while out.count < 3, let n = TimeLogic.next(rule, after: cursor, lat: nil, lon: nil) { out.append(n); cursor = n }
        return out
    }
}
