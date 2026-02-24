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


// MARK: - Prefixed Logger
/// A reusable logger that prefixes all messages. Replaces SandboxedLogger, DetectionPluginLogger, etc.
class PrefixedLogger: PluginLogger {
    private let prefix: String
    
    init(prefix: String) {
        self.prefix = prefix
    }
    
    /// Convenience initializer for plugin loggers
    convenience init(pluginId: String) {
        self.init(prefix: "[\(pluginId)]")
    }
    
    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        Logger.shared.log("\(prefix) \(message)", file: file, function: function, line: line)
    }
    
    var isDebugEnabled: Bool {
        return Logger.shared.isDebugEnabled
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
    
    /// Verbose modifier description (e.g. "Command ⌘ + Shift ⇧")
    var verboseDescription: String {
        var parts: [String] = []
        if contains(.command) { parts.append("Command ⌘") }
        if contains(.control) { parts.append("Control ⌃") }
        if contains(.option)  { parts.append("Option ⌥") }
        if contains(.shift)   { parts.append("Shift ⇧") }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }
}

// MARK: - Key Code Utilities

extension CGKeyCode {
    /// Convert a virtual key code to its string representation.
    /// Centralized here so all components share one mapping table.
    var displayString: String {
        let keyMap: [CGKeyCode: String] = [
            // Letters
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            // Numbers
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
            27: "-", 28: "8", 29: "0",
            // Symbols
            30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
            // Function keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
            100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15",
            // Special keys
            36: "\u{21a9}", 48: "\u{21e5}", 49: "Space", 51: "\u{232b}", 53: "\u{238b}", 117: "\u{2326}",
            123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
            115: "\u{2196}", 119: "\u{2198}", 116: "\u{21de}", 121: "\u{21df}"
        ]
        return keyMap[self] ?? "Key\(self)"
    }
}

// MARK: - CGEvent Utilities

/// Release all modifier keys (Command, Control, Option, Shift).
/// Shared by PluginSandbox and any code that needs to reset modifier state
/// before posting synthetic keyboard events.
///
/// Uses `.privateState` to post key-up events without inheriting physical state.
func releaseAllModifierKeys() {
    guard let source = CGEventSource(stateID: .privateState) else { return }
    let modifierKeys: [(CGKeyCode, CGKeyCode)] = [
        (0x37, 0x36), // Command L/R
        (0x3B, 0x3E), // Control L/R
        (0x3A, 0x3D), // Option L/R
        (0x38, 0x3C)  // Shift L/R
    ]
    for (left, right) in modifierKeys {
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: left, keyDown: false) {
            keyUp.flags = []; keyUp.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: right, keyDown: false) {
            keyUp.flags = []; keyUp.post(tap: .cghidEventTap)
        }
    }
    usleep(10_000)
}

// MARK: - Modifier Release Waiting

/// The modifier flags we care about for gesture triggers.
private let kModifierBits: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

/// Wait until ALL physical modifier keys are released, or until timeout.
/// Uses `CGEventSource.flagsState(.hidSystemState)` which is thread-safe and
/// reflects the actual HID hardware state (unlike NSEvent.modifierFlags which
/// may be stale on background threads).
///
/// Requires two consecutive clean reads separated by a short interval to avoid
/// false positives from momentary gaps between sequential key releases.
///
/// - Parameter timeout: Maximum time to wait (default 1.5s).
/// - Returns: `true` if all modifiers were released, `false` if timed out.
@discardableResult
func waitForModifierRelease(timeout: TimeInterval = 1.5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    var consecutiveClean = 0
    
    while Date() < deadline {
        let flags = CGEventSource.flagsState(.hidSystemState)
        let held = flags.intersection(kModifierBits)
        
        if held.isEmpty {
            consecutiveClean += 1
            // Require 2 consecutive clean reads (~20ms apart) to confirm
            if consecutiveClean >= 2 { return true }
        } else {
            consecutiveClean = 0
        }
        usleep(10_000) // 10ms poll
    }
    return false
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
