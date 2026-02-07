import Cocoa
import Carbon

extension NSEvent.ModifierFlags: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(UInt.self)
        self.init(rawValue: rawValue)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}


extension CGEventFlags: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(UInt64.self)
        self.init(rawValue: rawValue)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}


// Safe array subscript extension
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Shared Modifier Utilities

extension NSEvent.ModifierFlags {
    /// Strips device-specific and system bits, keeping only ⌘⌃⌥⇧.
    /// Use this everywhere modifiers need to be compared or stored.
    var normalized: NSEvent.ModifierFlags {
        var n: NSEvent.ModifierFlags = []
        if contains(.command) { n.insert(.command) }
        if contains(.control) { n.insert(.control) }
        if contains(.option)  { n.insert(.option) }
        if contains(.shift)   { n.insert(.shift) }
        return n
    }
    
    /// Returns the real-time modifier state from the OS.
    /// This is a direct system query — no cross-plugin dependency.
    static var currentSystem: NSEvent.ModifierFlags {
        return NSEvent.modifierFlags.normalized
    }
    
    /// Human-readable modifier string (e.g. "⌘⌃⇧")
    var symbolString: String {
        var parts: [String] = []
        if contains(.command) { parts.append("⌘") }
        if contains(.control) { parts.append("⌃") }
        if contains(.option)  { parts.append("⌥") }
        if contains(.shift)   { parts.append("⇧") }
        return parts.joined(separator: "")
    }
}

// MARK: - Shared Mouse Button Utilities

extension DragModifier {
    /// Returns the drag modifier corresponding to any currently pressed mouse button.
    /// Direct OS query via `NSEvent.pressedMouseButtons` — no plugin dependency.
    static var currentSystem: DragModifier {
        let pressed = NSEvent.pressedMouseButtons
        // Bit 0 = left, bit 1 = right, bit 2 = middle
        if pressed & (1 << 0) != 0 { return .leftDrag }
        if pressed & (1 << 1) != 0 { return .rightDrag }
        if pressed & (1 << 2) != 0 { return .middleDrag }
        return .none
    }
}
