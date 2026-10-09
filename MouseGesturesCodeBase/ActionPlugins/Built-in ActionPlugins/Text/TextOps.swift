import Foundation

/// Pure text transformations (no AppKit / app types), so they can be tested in isolation.
enum TextOps {

    // MARK: case

    static let caseStyles: [(id: String, label: String)] = [
        ("upper", "UPPERCASE"), ("lower", "lowercase"), ("title", "Title Case"), ("sentence", "Sentence case"),
        ("camel", "camelCase"), ("pascal", "PascalCase"), ("snake", "snake_case"), ("kebab", "kebab-case"),
        ("constant", "CONSTANT_CASE"), ("swap", "sWAP cASE"),
    ]

    static func changeCase(_ s: String, style: String) -> String {
        switch style {
        case "upper": return s.uppercased()
        case "lower": return s.lowercased()
        case "title": return s.lowercased().capitalized
        case "sentence": return sentenceCase(s)
        case "camel", "pascal", "snake", "kebab", "constant":
            // Convert each line separately so multi-line selections keep their structure.
            return s.components(separatedBy: "\n").map { identifierCase($0, style: style) }.joined(separator: "\n")
        case "swap": return String(s.map { $0.isUppercase ? Character($0.lowercased()) : ($0.isLowercase ? Character($0.uppercased()) : $0) })
        default: return s
        }
    }

    private static func sentenceCase(_ s: String) -> String {
        var out = "", capNext = true
        for ch in s.lowercased() {
            if capNext, ch.isLetter { out.append(contentsOf: ch.uppercased()); capNext = false }
            else { out.append(ch) }
            if ".!?".contains(ch) || ch == "\n" { capNext = true }
        }
        return out
    }

    /// Splits "someHTTPThing", "some-thing", "some thing", "some_thing" into lowercase words.
    static func words(_ s: String) -> [String] {
        var out: [String] = [], cur = ""
        let chars = Array(s)
        for (i, ch) in chars.enumerated() {
            if ch.isLetter || ch.isNumber {
                if ch.isUppercase, !cur.isEmpty {
                    let prevLower = chars[i - 1].isLowercase || chars[i - 1].isNumber
                    let nextLower = i + 1 < chars.count && chars[i + 1].isLowercase
                    if prevLower || (chars[i - 1].isUppercase && nextLower) { out.append(cur); cur = "" }
                }
                cur.append(ch)
            } else if !cur.isEmpty { out.append(cur); cur = "" }
        }
        if !cur.isEmpty { out.append(cur) }
        return out.map { $0.lowercased() }
    }

    private static func identifierCase(_ line: String, style: String) -> String {
        let w = words(line)
        guard !w.isEmpty else { return line }
        switch style {
        case "camel": return w[0] + w.dropFirst().map { $0.capitalized }.joined()
        case "pascal": return w.map { $0.capitalized }.joined()
        case "snake": return w.joined(separator: "_")
        case "kebab": return w.joined(separator: "-")
        default: return w.joined(separator: "_").uppercased()
        }
    }

    // MARK: cleaning

    static let cleanOps: [(id: String, label: String)] = [
        ("whitespace", "Clean whitespace"), ("trailing", "Trim trailing spaces"), ("unwrap", "Join broken lines into paragraphs"),
        ("strip_html", "Strip HTML tags"), ("strip_accents", "Remove accents"), ("strip_emoji", "Remove emoji"),
        ("ascii", "Replace fancy characters with plain ASCII"),
    ]

    static func clean(_ s: String, operation: String) -> String {
        switch operation {
        case "trailing": return s.components(separatedBy: "\n").map { $0.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression) }.joined(separator: "\n")
        case "unwrap": return unwrap(s)
        case "strip_html":
            return unescapeHTML(s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
        case "strip_accents": return s.folding(options: .diacriticInsensitive, locale: .current)
        case "strip_emoji":
            return String(s.unicodeScalars.filter { !($0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2000)) })
        case "ascii": return straighten(s).folding(options: .diacriticInsensitive, locale: .current)
        default: return whitespace(s)
        }
    }

    static func whitespace(_ s: String) -> String {
        var out: [String] = []
        for line in s.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            if t.isEmpty, out.last?.isEmpty ?? true { continue }
            out.append(t)
        }
        while out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n")
    }

    /// Single newlines inside a paragraph become spaces; blank lines still separate paragraphs.
    static func unwrap(_ s: String) -> String {
        s.components(separatedBy: "\n\n").map { para in
            para.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        }.joined(separator: "\n\n")
    }

    // MARK: typography

    static func smartTypography(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "\\.\\.\\.", with: "…", options: .regularExpression)
        t = t.replacingOccurrences(of: " ?--- ?", with: "—", options: .regularExpression)
        t = t.replacingOccurrences(of: " -- ", with: " – ")
        t = t.replacingOccurrences(of: "--", with: "—")
        t = t.replacingOccurrences(of: "(^|[\\s(\\[{\"“‘—–-])\"", with: "$1“", options: .regularExpression)
        t = t.replacingOccurrences(of: "\"", with: "”")
        t = t.replacingOccurrences(of: "(^|[\\s(\\[{“—–-])'", with: "$1‘", options: .regularExpression)
        t = t.replacingOccurrences(of: "'", with: "’")
        return t
    }

    static func straighten(_ s: String) -> String {
        let map: [(String, String)] = [("“", "\""), ("”", "\""), ("„", "\""), ("‘", "'"), ("’", "'"), ("‚", "'"),
                                       ("—", "--"), ("–", "-"), ("…", "..."), ("\u{00A0}", " "), ("\u{2009}", " "), ("•", "*")]
        return map.reduce(s) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    // MARK: lines

    static let sortOrders: [(id: String, label: String)] = [
        ("az", "A → Z"), ("za", "Z → A"), ("numeric", "Numeric"), ("length", "By length"), ("natural", "Natural (file2 before file10)"),
    ]

    static func sortLines(_ s: String, order: String) -> String {
        let lines = s.components(separatedBy: "\n")
        let sorted: [String]
        switch order {
        case "za": sorted = lines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedDescending }
        case "numeric": sorted = lines.sorted { (Double($0.trimmingCharacters(in: .whitespaces)) ?? .infinity) < (Double($1.trimmingCharacters(in: .whitespaces)) ?? .infinity) }
        case "length": sorted = lines.sorted { $0.count < $1.count }
        case "natural": sorted = lines.sorted { $0.compare($1, options: [.numeric, .caseInsensitive]) == .orderedAscending }
        default: sorted = lines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        return sorted.joined(separator: "\n")
    }

    static let lineOps: [(id: String, label: String)] = [
        ("dedupe", "Remove duplicate lines"), ("remove_blank", "Remove blank lines"), ("reverse", "Reverse line order"),
        ("shuffle", "Shuffle lines"), ("number", "Number lines"), ("join_space", "Join lines with spaces"),
        ("join_comma", "Join lines with commas"), ("split_comma", "Split commas into lines"), ("indent", "Indent"), ("outdent", "Outdent"),
    ]

    static func editLines(_ s: String, operation: String, seed: UInt64? = nil) -> String {
        let lines = s.components(separatedBy: "\n")
        switch operation {
        case "dedupe":
            var seen = Set<String>(); return lines.filter { seen.insert($0).inserted }.joined(separator: "\n")
        case "remove_blank": return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
        case "reverse": return lines.reversed().joined(separator: "\n")
        case "shuffle":
            if let seed = seed { var g = SeededGenerator(seed: seed); return lines.shuffled(using: &g).joined(separator: "\n") }
            return lines.shuffled().joined(separator: "\n")
        case "number":
            let w = String(lines.count).count
            return lines.enumerated().map { "\(String($0.offset + 1).leftPad(w)). \($0.element)" }.joined(separator: "\n")
        case "join_space": return lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        case "join_comma": return lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
        case "split_comma": return s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        case "indent": return lines.map { $0.isEmpty ? $0 : "    " + $0 }.joined(separator: "\n")
        case "outdent":
            return lines.map { l in
                if l.hasPrefix("\t") { return String(l.dropFirst()) }
                var n = 0; for ch in l.prefix(4) { if ch == " " { n += 1 } else { break } }
                return String(l.dropFirst(n))
            }.joined(separator: "\n")
        default: return s
        }
    }

    static func prefixSuffix(_ s: String, prefix: String, suffix: String) -> String {
        s.components(separatedBy: "\n").map { $0.isEmpty ? $0 : prefix + $0 + suffix }.joined(separator: "\n")
    }

    // MARK: wrap / markdown

    static let wrapStyles: [(id: String, label: String)] = [
        ("double", "\"Double quotes\""), ("single", "'Single quotes'"), ("smart_double", "“Curly quotes”"), ("paren", "(Parentheses)"),
        ("bracket", "[Brackets]"), ("brace", "{Braces}"), ("angle", "<Angle brackets>"), ("backtick", "`Inline code`"),
        ("bold", "**Bold**"), ("italic", "*Italic*"), ("strike", "~~Strikethrough~~"),
    ]

    static func wrap(_ s: String, style: String) -> String {
        let pairs: [String: (String, String)] = [
            "double": ("\"", "\""), "single": ("'", "'"), "smart_double": ("“", "”"), "paren": ("(", ")"), "bracket": ("[", "]"),
            "brace": ("{", "}"), "angle": ("<", ">"), "backtick": ("`", "`"), "bold": ("**", "**"), "italic": ("*", "*"), "strike": ("~~", "~~"),
        ]
        guard let (a, b) = pairs[style] else { return s }
        return a + s + b
    }

    static let markdownKinds: [(id: String, label: String)] = [
        ("bullets", "Bulleted list"), ("numbered", "Numbered list"), ("checklist", "Checklist"), ("quote", "Block quote"),
        ("code_block", "Code block"), ("h1", "Heading 1"), ("h2", "Heading 2"), ("h3", "Heading 3"), ("link", "Link (URL from clipboard)"),
        ("unlist", "Remove list/quote markers"),
    ]

    static func markdown(_ s: String, kind: String, url: String = "") -> String {
        let lines = s.components(separatedBy: "\n")
        switch kind {
        case "bullets": return lines.map { $0.isEmpty ? $0 : "- " + $0 }.joined(separator: "\n")
        case "numbered":
            var n = 0; return lines.map { l in if l.isEmpty { return l }; n += 1; return "\(n). \(l)" }.joined(separator: "\n")
        case "checklist": return lines.map { $0.isEmpty ? $0 : "- [ ] " + $0 }.joined(separator: "\n")
        case "quote": return lines.map { "> " + $0 }.joined(separator: "\n")
        case "code_block": return "```\n" + s + "\n```"
        case "h1": return "# " + s
        case "h2": return "## " + s
        case "h3": return "### " + s
        case "link": return "[\(s)](\(url.trimmingCharacters(in: .whitespacesAndNewlines)))"
        case "unlist":
            return lines.map { $0.replacingOccurrences(of: "^\\s*(?:[-*+•]|\\d+[.)]|>)\\s*(?:\\[[ xX]\\]\\s*)?", with: "", options: .regularExpression) }.joined(separator: "\n")
        default: return s
        }
    }

    // MARK: encode / decode

    static let encodings: [(id: String, label: String)] = [
        ("url_encode", "URL-encode"), ("url_decode", "URL-decode"), ("base64_encode", "Base64 encode"), ("base64_decode", "Base64 decode"),
        ("html_escape", "HTML-escape"), ("html_unescape", "HTML-unescape"), ("rot13", "ROT13"), ("reverse", "Reverse text"),
    ]

    static func encode(_ s: String, kind: String) -> String? {
        switch kind {
        case "url_encode": return s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))
        case "url_decode": return s.removingPercentEncoding
        case "base64_encode": return Data(s.utf8).base64EncodedString()
        case "base64_decode":
            guard let d = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)), let r = String(data: d, encoding: .utf8) else { return nil }
            return r
        case "html_escape":
            return s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        case "html_unescape": return unescapeHTML(s)
        case "rot13":
            return String(s.unicodeScalars.map { u -> Character in
                switch u.value {
                case 65...90: return Character(UnicodeScalar((u.value - 65 + 13) % 26 + 65)!)
                case 97...122: return Character(UnicodeScalar((u.value - 97 + 13) % 26 + 97)!)
                default: return Character(u)
                }
            })
        case "reverse": return String(s.reversed())
        default: return s
        }
    }

    static func unescapeHTML(_ s: String) -> String {
        var t = s
        for (k, v) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        return t
    }

    static func formatJSON(_ s: String, minify: Bool) -> String? {
        guard let d = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: obj, options: minify ? [.fragmentsAllowed, .sortedKeys] : [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
        else { return nil }
        return String(data: out, encoding: .utf8)
    }

    static func slugify(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        return folded.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    // MARK: stats

    static func stats(_ s: String) -> String {
        let chars = s.count
        let words = s.split { $0.isWhitespace || $0.isNewline }.count
        let lines = s.isEmpty ? 0 : s.components(separatedBy: "\n").count
        let minutes = Double(words) / 230
        let reading = minutes < 1 ? "under a minute" : "\(Int(minutes.rounded())) min"
        return "\(words) words · \(chars) characters · \(lines) line\(lines == 1 ? "" : "s") · \(reading) read"
    }

    // MARK: calculator

    /// Evaluates + − × ÷ * / ^ % ( ) and decimals. Returns nil for anything else.
    static func calculate(_ input: String) -> Double? {
        var p = ExprParser(Array(input.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: ",", with: "").filter { !$0.isWhitespace }))
        guard let v = p.expression(), p.atEnd, v.isFinite else { return nil }
        return v
    }

    static func formatNumber(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int(v)) }
        var s = String(format: "%.10f", v)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }


    // MARK: units + timestamps

    private static let unitTable: [String: Dimension] = {
        var t: [String: Dimension] = [:]
        func add(_ names: [String], _ u: Dimension) { for n in names { t[n] = u } }
        add(["m", "meter", "meters", "metre", "metres"], UnitLength.meters); add(["km", "kilometer", "kilometers", "kilometre", "kilometres"], UnitLength.kilometers)
        add(["cm", "centimeter", "centimeters"], UnitLength.centimeters); add(["mm", "millimeter", "millimeters"], UnitLength.millimeters)
        add(["mi", "mile", "miles"], UnitLength.miles); add(["yd", "yard", "yards"], UnitLength.yards)
        add(["ft", "foot", "feet"], UnitLength.feet); add(["in", "inch", "inches"], UnitLength.inches)
        add(["kg", "kilogram", "kilograms", "kilo", "kilos"], UnitMass.kilograms); add(["g", "gram", "grams"], UnitMass.grams); add(["mg", "milligram", "milligrams"], UnitMass.milligrams)
        add(["lb", "lbs", "pound", "pounds"], UnitMass.pounds); add(["oz", "ounce", "ounces"], UnitMass.ounces); add(["st", "stone"], UnitMass.stones)
        add(["c", "°c", "celsius"], UnitTemperature.celsius); add(["f", "°f", "fahrenheit"], UnitTemperature.fahrenheit); add(["k", "kelvin"], UnitTemperature.kelvin)
        add(["l", "liter", "liters", "litre", "litres"], UnitVolume.liters); add(["ml", "milliliter", "milliliters"], UnitVolume.milliliters)
        add(["gal", "gallon", "gallons"], UnitVolume.gallons); add(["qt", "quart", "quarts"], UnitVolume.quarts); add(["pt", "pint", "pints"], UnitVolume.pints)
        add(["cup", "cups"], UnitVolume.cups); add(["floz", "fl oz"], UnitVolume.fluidOunces); add(["tbsp", "tablespoon", "tablespoons"], UnitVolume.tablespoons); add(["tsp", "teaspoon", "teaspoons"], UnitVolume.teaspoons)
        add(["m/s", "mps"], UnitSpeed.metersPerSecond); add(["km/h", "kph", "kmh", "kmph"], UnitSpeed.kilometersPerHour); add(["mph", "mi/h"], UnitSpeed.milesPerHour); add(["kn", "kt", "knot", "knots"], UnitSpeed.knots)
        add(["s", "sec", "secs", "second", "seconds"], UnitDuration.seconds); add(["min", "mins", "minute", "minutes"], UnitDuration.minutes); add(["h", "hr", "hrs", "hour", "hours"], UnitDuration.hours)
        add(["b", "byte", "bytes"], UnitInformationStorage.bytes); add(["kb", "kilobyte", "kilobytes"], UnitInformationStorage.kilobytes); add(["mb", "megabyte", "megabytes"], UnitInformationStorage.megabytes)
        add(["gb", "gigabyte", "gigabytes"], UnitInformationStorage.gigabytes); add(["tb", "terabyte", "terabytes"], UnitInformationStorage.terabytes)
        add(["ha", "hectare", "hectares"], UnitArea.hectares); add(["acre", "acres"], UnitArea.acres); add(["m2", "m²", "sqm"], UnitArea.squareMeters); add(["ft2", "ft²", "sqft"], UnitArea.squareFeet); add(["km2", "km²"], UnitArea.squareKilometers)
        return t
    }()

    /// "5 km to mi" → "3.10686 mi". With `target`, the text is just "5 km". nil when not understood or the units don't match.
    static func convertUnits(_ input: String, target: String? = nil) -> (value: String, result: String)? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var toUnit = target?.trimmingCharacters(in: .whitespaces).lowercased()
        if toUnit == nil || toUnit!.isEmpty {
            guard let r = s.range(of: "\\s+(?:to|in|into|as|->|→)\\s+(\\S+)$", options: .regularExpression) else { return nil }
            toUnit = String(s[r]).components(separatedBy: .whitespaces).last
            s = String(s[..<r.lowerBound])
        }
        guard let to = toUnit, let m = s.range(of: "^(-?[0-9][0-9,]*\\.?[0-9]*(?:e-?[0-9]+)?)\\s*(.+)$", options: .regularExpression) else { return nil }
        let whole = String(s[m])
        let numEnd = whole.firstIndex { !("0123456789,.-e".contains($0)) } ?? whole.endIndex
        guard let value = Double(String(whole[..<numEnd]).replacingOccurrences(of: ",", with: "")) else { return nil }
        let fromName = String(whole[numEnd...]).trimmingCharacters(in: .whitespaces)
        guard let from = unitTable[fromName], let dest = unitTable[to], type(of: from) == type(of: dest) else { return nil }
        let converted = Measurement(value: value, unit: from).converted(to: dest).value
        let digits = String(format: "%.6g", converted)
        let shown = digits.contains("e") ? digits : (Double(digits).map { formatNumber($0) } ?? digits)
        let typedTarget = target.map { $0.trimmingCharacters(in: .whitespaces) } ?? input.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).last ?? to
        return (formatNumber(value), shown + " " + typedTarget)
    }

    /// Unix seconds/milliseconds → local ISO date-time; an ISO date/date-time → unix seconds.
    static func convertTimestamp(_ input: String, calendar: Calendar = .current) -> String? {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = calendar; f.timeZone = calendar.timeZone
        if let n = Double(t), t.count >= 9 {
            let secs = t.count >= 13 ? n / 1000 : n
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: Date(timeIntervalSince1970: secs))
        }
        for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return String(Int(d.timeIntervalSince1970)) }
        }
        if let d = ISO8601DateFormatter().date(from: t) { return String(Int(d.timeIntervalSince1970)) }
        return nil
    }

    // MARK: insert

    static let dateFormats: [(id: String, label: String, pattern: String)] = [
        ("iso_date", "2026-10-09", "yyyy-MM-dd"), ("iso_datetime", "2026-10-09 14:30", "yyyy-MM-dd HH:mm"),
        ("long_date", "October 9, 2026", "MMMM d, yyyy"), ("us_date", "10/09/2026", "MM/dd/yyyy"),
        ("weekday", "Friday, October 9", "EEEE, MMMM d"), ("time_24h", "14:30", "HH:mm"), ("time_12h", "2:30 PM", "h:mm a"),
        ("filename", "20261009-143000", "yyyyMMdd-HHmmss"), ("iso8601", "2026-10-09T14:30:00Z", "@iso"), ("unix", "Unix timestamp", "@unix"),
    ]

    static func renderDate(format id: String, at date: Date) -> String {
        guard let f = dateFormats.first(where: { $0.id == id }) ?? dateFormats.first else { return "" }
        if f.pattern == "@unix" { return String(Int(date.timeIntervalSince1970)) }
        if f.pattern == "@iso" { return ISO8601DateFormatter().string(from: date) }
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = f.pattern
        return df.string(from: date)
    }

    static func expand(_ template: String, at date: Date, clipboard: String) -> String {
        template
            .replacingOccurrences(of: "{date}", with: renderDate(format: "iso_date", at: date))
            .replacingOccurrences(of: "{time}", with: renderDate(format: "time_24h", at: date))
            .replacingOccurrences(of: "{datetime}", with: renderDate(format: "iso_datetime", at: date))
            .replacingOccurrences(of: "{uuid}", with: UUID().uuidString)
            .replacingOccurrences(of: "{clipboard}", with: clipboard)
    }

    static func lorem(sentences: Int) -> String {
        let bank = ["Lorem ipsum dolor sit amet, consectetur adipiscing elit.", "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
                    "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
                    "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.",
                    "Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."]
        return (0..<max(1, sentences)).map { bank[$0 % bank.count] }.joined(separator: " ")
    }
}

extension String {
    fileprivate func leftPad(_ n: Int) -> String { String(repeating: " ", count: max(0, n - count)) + self }
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 { state ^= state << 13; state ^= state >> 7; state ^= state << 17; return state }
}

/// Recursive-descent arithmetic: expr = term {(+|-) term}; term = pow {(*|/|%) pow}; pow = unary [^ pow].
struct ExprParser {
    let c: [Character]; var i = 0
    init(_ c: [Character]) { self.c = c }
    var atEnd: Bool { i >= c.count }

    mutating func expression() -> Double? {
        guard var v = term() else { return nil }
        while i < c.count, c[i] == "+" || c[i] == "-" {
            let op = c[i]; i += 1
            guard let r = term() else { return nil }
            v = op == "+" ? v + r : v - r
        }
        return v
    }
    mutating func term() -> Double? {
        guard var v = power() else { return nil }
        while i < c.count, "*/%x".contains(c[i]) {
            let op = c[i]; i += 1
            guard let r = power() else { return nil }
            switch op { case "/": guard r != 0 else { return nil }; v /= r
                        case "%": guard r != 0 else { return nil }; v = v.truncatingRemainder(dividingBy: r)
                        default: v *= r }
        }
        return v
    }
    mutating func power() -> Double? {
        guard let b = unary() else { return nil }
        if i < c.count, c[i] == "^" { i += 1; guard let e = power() else { return nil }; return pow(b, e) }
        return b
    }
    mutating func unary() -> Double? {
        if i < c.count, c[i] == "-" { i += 1; return unary().map { -$0 } }
        if i < c.count, c[i] == "+" { i += 1; return unary() }
        return atom()
    }
    mutating func atom() -> Double? {
        if i < c.count, c[i] == "(" {
            i += 1; guard let v = expression(), i < c.count, c[i] == ")" else { return nil }
            i += 1; return v
        }
        var s = ""
        while i < c.count, c[i].isNumber || c[i] == "." { s.append(c[i]); i += 1 }
        if i < c.count, c[i] == "%", s != "" , !(i + 1 < c.count && (c[i + 1].isNumber || c[i + 1] == "(" || c[i + 1] == ".")) { i += 1; return Double(s).map { $0 / 100 } }
        return Double(s)
    }
}
