import Foundation

/// Pure formatting for captured text.
enum CaptureFormat {
    static let styles: [(id: String, label: String)] = [
        ("plain", "Plain text"), ("bullet", "Bullet"), ("task", "Task  - [ ]"), ("quote", "Quote  >"), ("stamped", "Bullet with date and time"),
    ]

    /// One entry as it is appended to the inbox. `source` (app name) is added in parentheses when given.
    static func entry(_ text: String, style: String, date: Date, source: String?) -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = body.components(separatedBy: "\n")
        let tail = source.map { " (\($0))" } ?? ""
        switch style {
        case "bullet": return "- " + lines.joined(separator: "\n  ") + tail
        case "task": return "- [ ] " + lines.joined(separator: "\n  ") + tail
        case "quote": return lines.map { "> " + $0 }.joined(separator: "\n") + (source.map { "\n> — \($0)" } ?? "")
        case "stamped": return "- \(stamp(date)) " + lines.joined(separator: "\n  ") + tail
        default: return body + tail
        }
    }

    static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    /// "20261009-143000 first words of the note.md"
    static func noteFileName(_ text: String, date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        let words = text.split { !($0.isLetter || $0.isNumber) }.prefix(6).joined(separator: " ")
        return f.string(from: date) + (words.isEmpty ? "" : " " + words.prefix(50)) + ".md"
    }

    /// Escapes text for use inside an AppleScript string literal.
    static func appleScriptString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// First line as a title, the rest as the body.
    static func titleAndBody(_ text: String) -> (String, String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = t.components(separatedBy: "\n")
        let title = String(parts[0].prefix(120))
        return (title, parts.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
