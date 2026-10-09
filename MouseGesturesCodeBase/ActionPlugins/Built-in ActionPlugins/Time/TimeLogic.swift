import Foundation

/// Pure date/time helpers for Timers & Alarms (built in) and the library Scheduler plugin, which compiles this very file
/// through the `Plugins/shared/TimeLogic.swift` symlink — keep it free of app types.
/// Weekdays use Foundation numbering: 1 = Sunday … 7 = Saturday.
enum TimeLogic {

    // MARK: clock times

    /// "7", "7pm", "7:30 pm", "19:30", "noon", "midnight" → (hour, minute).
    static func parseClock(_ raw: String) -> (hour: Int, minute: Int)? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ".", with: "")
        if s == "noon" { return (12, 0) }
        if s == "midnight" { return (0, 0) }
        guard let m = s.range(of: "^(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?$", options: .regularExpression) else { return nil }
        let parts = String(s[m]).replacingOccurrences(of: " ", with: "")
        let digits = parts.components(separatedBy: CharacterSet(charactersIn: ":apm")).filter { !$0.isEmpty }
        guard var h = Int(digits[0]) else { return nil }
        let min = digits.count > 1 ? Int(digits[1]) ?? -1 : 0
        guard min >= 0, min < 60 else { return nil }
        if parts.hasSuffix("pm") { guard (1...12).contains(h) else { return nil }; if h != 12 { h += 12 } }
        else if parts.hasSuffix("am") { guard (1...12).contains(h) else { return nil }; if h == 12 { h = 0 } }
        guard (0..<24).contains(h) else { return nil }
        return (h, min)
    }

    static let dayNames = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7,
                           "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
                           "tues": 3, "thur": 5, "thurs": 5]
    static let allDays: Set<Int> = Set(1...7)

    /// "weekdays", "weekends", "daily", "mon,wed,fri", "mon-fri".
    static func parseDays(_ raw: String) -> Set<Int>? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        switch s {
        case "weekdays", "weekday": return [2, 3, 4, 5, 6]
        case "weekends", "weekend": return [1, 7]
        case "daily", "every day", "everyday": return allDays
        default: break
        }
        var out = Set<Int>()
        for part in s.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if part.contains("-") {
                let ends = part.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
                guard ends.count == 2, let a = dayNames[ends[0]], let b = dayNames[ends[1]] else { return nil }
                var d = a; out.insert(d)
                while d != b { d = d % 7 + 1; out.insert(d) }
            } else if let d = dayNames[part] { out.insert(d) } else { return nil }
        }
        return out.isEmpty ? nil : out
    }

    // MARK: durations

    /// "90s", "5m", "5 min", "2h", "1.5 hours", "1h30m" → seconds.
    static func parseDuration(_ raw: String) -> TimeInterval? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        let re = try! NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)\\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)", options: [])
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        // the whole string must be consumed by duration terms
        let consumed = matches.reduce(0) { $0 + $1.range.length } + s.filter { $0 == " " }.count
        guard consumed >= s.count else { return nil }
        var total = 0.0
        for m in matches {
            let n = Double(ns.substring(with: m.range(at: 1)))!
            switch ns.substring(with: m.range(at: 2)).first! { case "h": total += n * 3600; case "m": total += n * 60; default: total += n }
        }
        return total
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        if s >= 3600 { return "\(s / 3600) h" + (s % 3600 >= 60 ? " \((s % 3600) / 60) min" : "") }
        if s >= 60 { return "\(s / 60) min" + (s % 60 > 0 ? " \(s % 60) s" : "") }
        return "\(s) s"
    }

    static func clockString(_ date: Date) -> String {
        let df = DateFormatter(); df.locale = Locale.current; df.dateStyle = .none; df.timeStyle = .short
        return df.string(from: date)
    }

    // MARK: next occurrence

    /// First time strictly after `after` that falls on one of `days` at hour:minute.
    static func nextClock(hour: Int, minute: Int, days: Set<Int>, after: Date, calendar: Calendar = .current) -> Date? {
        guard !days.isEmpty else { return nil }
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: after),
                  calendar.component(.weekday, from: day) != 0, days.contains(calendar.component(.weekday, from: day)),
                  let d = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), d > after else { continue }
            return d
        }
        return nil
    }

    // MARK: schedule rules (Scheduler plugin)

    enum Rule: Equatable {
        case clock(hour: Int, minute: Int, days: Set<Int>)
        case every(seconds: TimeInterval, days: Set<Int>, window: (start: Int, end: Int)?)   // window in minutes since midnight
        case solar(sunrise: Bool, offset: TimeInterval, days: Set<Int>)
        case monthly(day: Int, hour: Int, minute: Int)
        case once(Date)

        static func == (l: Rule, r: Rule) -> Bool { "\(l)" == "\(r)" }
    }

    /// Grammar (case-insensitive):
    ///   [days] 8:30 | 7pm | noon            → clock          e.g. "weekdays 8:30", "mon,wed,fri 7pm"
    ///   [days] every 30 min [9:00-17:00]    → interval aligned to midnight, optional window
    ///   [days] sunrise|sunset [+/-30m]      → solar (needs latitude/longitude)
    ///   monthly 15 9:00                     → day of month
    ///   2026-12-25 08:00                    → one-off
    static func parseRule(_ raw: String) -> Rule? {
        var s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }

        if let m = s.range(of: "^\\d{4}-\\d{2}-\\d{2}\\s+\\S+(\\s*(am|pm))?$", options: .regularExpression), m.lowerBound == s.startIndex {
            let parts = s.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let clock = parseClock(parts[1]) else { return nil }
            let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd HH:mm"
            return df.date(from: String(format: "%@ %02d:%02d", parts[0], clock.hour, clock.minute)).map { .once($0) }
        }
        if s.hasPrefix("monthly ") {
            let parts = s.dropFirst(8).split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let day = Int(parts[0].replacingOccurrences(of: "st", with: "").replacingOccurrences(of: "nd", with: "").replacingOccurrences(of: "rd", with: "").replacingOccurrences(of: "th", with: "")),
                  (1...31).contains(day), let c = parseClock(parts[1]) else { return nil }
            return .monthly(day: day, hour: c.hour, minute: c.minute)
        }

        // optional leading days
        var days = allDays
        for prefix in ["weekdays", "weekends", "daily", "every day"] where s.hasPrefix(prefix + " ") {
            days = parseDays(prefix)!; s = String(s.dropFirst(prefix.count + 1)).trimmingCharacters(in: .whitespaces)
        }
        if days == allDays, let sp = s.firstIndex(of: " "), let d = parseDays(String(s[..<sp])), !s.hasPrefix("every") {
            days = d; s = String(s[s.index(after: sp)...]).trimmingCharacters(in: .whitespaces)
        }

        if s.hasPrefix("sunrise") || s.hasPrefix("sunset") {
            let isRise = s.hasPrefix("sunrise")
            let rest = s.dropFirst(isRise ? 7 : 6).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return .solar(sunrise: isRise, offset: 0, days: days) }
            guard let sign = rest.first, sign == "+" || sign == "-", let dur = parseDuration(String(rest.dropFirst())) else { return nil }
            return .solar(sunrise: isRise, offset: sign == "-" ? -dur : dur, days: days)
        }
        if s.hasPrefix("every ") {
            var body = String(s.dropFirst(6)); var window: (Int, Int)?
            if let r = body.range(of: "(?:between\\s+)?(\\S+)\\s*(?:-|to|and)\\s*(\\S+)$", options: .regularExpression) {
                let w = String(body[r]).replacingOccurrences(of: "between", with: "").trimmingCharacters(in: .whitespaces)
                let ends = w.components(separatedBy: CharacterSet(charactersIn: "- ")).filter { !$0.isEmpty && $0 != "to" && $0 != "and" }
                if ends.count == 2, let a = parseClock(ends[0]), let b = parseClock(ends[1]) { window = (a.hour * 60 + a.minute, b.hour * 60 + b.minute); body = String(body[..<r.lowerBound]) }
            }
            let dur = parseDuration(body.trimmingCharacters(in: .whitespaces).isEmpty ? "1h" : body) ?? (body.trimmingCharacters(in: .whitespaces) == "hour" ? 3600 : body.trimmingCharacters(in: .whitespaces) == "minute" ? 60 : nil)
            guard let seconds = dur, seconds >= 60 else { return nil }
            return .every(seconds: seconds, days: days, window: window)
        }
        guard let c = parseClock(s) else { return nil }
        return .clock(hour: c.hour, minute: c.minute, days: days)
    }

    /// Next firing strictly after `after`. `lat`/`lon` are only needed for solar rules.
    static func next(_ rule: Rule, after: Date, lat: Double?, lon: Double?, calendar: Calendar = .current) -> Date? {
        switch rule {
        case .clock(let h, let m, let days): return nextClock(hour: h, minute: m, days: days, after: after, calendar: calendar)
        case .once(let d): return d > after ? d : nil
        case .monthly(let day, let h, let m):
            for offset in 0...370 {
                guard let d = calendar.date(byAdding: .day, value: offset, to: after), calendar.component(.day, from: d) == day,
                      let t = calendar.date(bySettingHour: h, minute: m, second: 0, of: d), t > after else { continue }
                return t
            }
            return nil
        case .every(let seconds, let days, let window):
            var cursor = after
            for pass in 0..<9 {
                let start = calendar.startOfDay(for: cursor)
                // first day: strictly after `after`; later days start at midnight itself
                var k = pass == 0 ? (cursor.timeIntervalSince(start) / seconds).rounded(.down) + 1 : 0
                while true {
                    let t = start.addingTimeInterval(k * seconds)
                    if t >= (calendar.date(byAdding: .day, value: 1, to: start) ?? t.addingTimeInterval(86400)) { break }
                    let mins = Int(t.timeIntervalSince(start) / 60)
                    let inWindow = window.map { $0.start <= $0.end ? (mins >= $0.start && mins <= $0.end) : (mins >= $0.start || mins <= $0.end) } ?? true
                    if inWindow, days.contains(calendar.component(.weekday, from: t)), t > after { return t }
                    k += 1
                }
                cursor = calendar.date(byAdding: .day, value: 1, to: start)!
            }
            return nil
        case .solar(let rise, let offset, let days):
            guard let lat = lat, let lon = lon else { return nil }
            for dayOffset in -1...8 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: after),
                      days.contains(calendar.component(.weekday, from: day)),
                      let t = solarEvent(rise: rise, on: day, lat: lat, lon: lon, calendar: calendar)?.addingTimeInterval(offset), t > after else { continue }
                return t
            }
            return nil
        }
    }

    // MARK: sunrise / sunset (NOAA approximation, ±2 min)

    static func solarEvent(rise: Bool, on date: Date, lat: Double, lon: Double, calendar: Calendar = .current) -> Date? {
        let rad = Double.pi / 180
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        guard let noonUTC = utc.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12)) else { return nil }
        let jd = noonUTC.timeIntervalSince1970 / 86400 + 2440587.5
        let n = jd - 2451545.0 + 0.0008
        let jStar = n - lon / 360
        let M = (357.5291 + 0.98560028 * jStar).truncatingRemainder(dividingBy: 360)
        let C = 1.9148 * sin(M * rad) + 0.02 * sin(2 * M * rad) + 0.0003 * sin(3 * M * rad)
        let lambda = (M + C + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let jTransit = 2451545.0 + jStar + 0.0053 * sin(M * rad) - 0.0069 * sin(2 * lambda * rad)
        let decl = asin(sin(lambda * rad) * sin(23.4397 * rad))
        let cosH = (sin(-0.833 * rad) - sin(lat * rad) * sin(decl)) / (cos(lat * rad) * cos(decl))
        guard cosH >= -1, cosH <= 1 else { return nil }   // polar day / night
        let H = acos(cosH) / rad
        let j = rise ? jTransit - H / 360 : jTransit + H / 360
        return Date(timeIntervalSince1970: (j - 2440587.5) * 86400)
    }

    static func describe(_ rule: Rule) -> String {
        func dayText(_ d: Set<Int>) -> String { d == allDays ? "every day" : d == [2, 3, 4, 5, 6] ? "weekdays" : d == [1, 7] ? "weekends" : "selected days" }
        switch rule {
        case .clock(let h, let m, let d): return String(format: "%02d:%02d, %@", h, m, dayText(d))
        case .every(let s, let d, let w):
            return "every \(formatDuration(s)), \(dayText(d))" + (w.map { String(format: ", %02d:%02d–%02d:%02d", $0.start / 60, $0.start % 60, $0.end / 60, $0.end % 60) } ?? "")
        case .solar(let r, let o, let d): return (r ? "sunrise" : "sunset") + (o == 0 ? "" : (o > 0 ? " +" : " −") + formatDuration(abs(o))) + ", " + dayText(d)
        case .monthly(let day, let h, let m): return String(format: "day %d of each month at %02d:%02d", day, h, m)
        case .once(let d): return "once, " + d.formatted(date: .abbreviated, time: .shortened)
        }
    }
}
