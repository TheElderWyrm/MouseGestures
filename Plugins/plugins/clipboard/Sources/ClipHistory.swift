import Foundation

/// Most-recent-first list of copied text. Pure, so it can be tested without a pasteboard.
struct ClipHistory {
    private(set) var items: [String] = []
    var limit: Int

    init(limit: Int = 20) { self.limit = max(1, limit) }

    /// Adds a clip at the front. Returns false for empty/oversized text. A repeat moves to the front.
    @discardableResult
    mutating func add(_ text: String, maxLength: Int = 20_000) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= maxLength else { return false }
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        return true
    }

    mutating func clear() { items.removeAll() }
    mutating func setLimit(_ n: Int) { limit = max(1, n); if items.count > limit { items.removeLast(items.count - limit) } }

    /// Single-line label for a menu: whitespace collapsed, cut to `length` characters.
    static func label(_ text: String, length: Int = 60) -> String {
        let flat = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return flat.count > length ? String(flat.prefix(length - 1)) + "…" : flat
    }
}
