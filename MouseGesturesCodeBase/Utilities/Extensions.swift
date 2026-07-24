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
        if contains(.option) { n.insert(.option) }
        if contains(.shift) { n.insert(.shift) }
        return n
    }

    /// Returns the real-time modifier state from the OS.
    /// This is a direct system query — no cross-plugin dependency.
    static var currentSystem: NSEvent.ModifierFlags {
        return NSEvent.modifierFlags.normalized
    }

    /// Returns which modifier keys are physically held, with this app's own
    /// in-flight synthetic keyboard shortcuts masked out.
    ///
    /// Empirically confirmed (standalone probe, zero physical keys held):
    /// posting ANY CGEvent with a non-empty `.flags` field — even for an
    /// unrelated, non-modifier key, like the "T" keyDown `sendKeyboardShortcut`
    /// posts for Cmd+T — writes those specific bits into the shared HID
    /// key-state table. This is true of `CGEventSource.flagsState(_:)` AND
    /// `CGEventSource.keyState(_:key:)` (tested both), and of every tap level
    /// (`.cghidEventTap`, `.cgSessionEventTap`, `postToPid` — tested all
    /// three): there is no CGEvent-posting mechanism that avoids it. It's not
    /// a per-API quirk, it's how `.flags` and modifier key-state are the same
    /// underlying data at the OS level.
    ///
    /// `sendKeyboardShortcut` corrects the actual OS-level state immediately
    /// afterward (see `clearModifierStateContamination`), but that correction
    /// is itself a posted CGEvent — it lands after some non-zero, real
    /// latency, not instantly. During that gap this app's own detection code
    /// would otherwise see the same corruption it just caused. Subtracting
    /// `SyntheticModifierSuppression`'s currently-suppressed bits here closes
    /// that gap with zero added latency (an in-memory check, not another
    /// OS round-trip): `sendKeyboardShortcut` records exactly which bits it
    /// is about to perturb and for how long *before* posting anything, so
    /// this always has current, correct information — it is not re-checking
    /// an uncertain reading, it is excluding a window this app already knows
    /// it caused.
    static var currentHardware: NSEvent.ModifierFlags {
        let source = CGEventSourceStateID.hidSystemState
        var flags: NSEvent.ModifierFlags = []
        if CGEventSource.keyState(source, key: 0x37) || CGEventSource.keyState(source, key: 0x36) { flags.insert(.command) }
        if CGEventSource.keyState(source, key: 0x3B) || CGEventSource.keyState(source, key: 0x3E) { flags.insert(.control) }
        if CGEventSource.keyState(source, key: 0x3A) || CGEventSource.keyState(source, key: 0x3D) { flags.insert(.option) }
        if CGEventSource.keyState(source, key: 0x38) || CGEventSource.keyState(source, key: 0x3C) { flags.insert(.shift) }
        return flags.subtracting(SyntheticModifierSuppression.shared.currentlySuppressed)
    }

    /// Human-readable modifier string (e.g. "⌘⌃⇧")
    var symbolString: String {
        var parts: [String] = []
        if contains(.command) { parts.append("⌘") }
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        return parts.joined(separator: "")
    }

    /// Verbose modifier description (e.g. "Command ⌘ + Shift ⇧")
    var verboseDescription: String {
        var parts: [String] = []
        if contains(.command) { parts.append("Command ⌘") }
        if contains(.control) { parts.append("Control ⌃") }
        if contains(.option) { parts.append("Option ⌥") }
        if contains(.shift) { parts.append("Shift ⇧") }
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

/// Cleans up a specific, confirmed side effect of posting ANY CGEvent with a
/// non-empty `.flags` field — even for a key that isn't a modifier at all.
///
/// Root cause, confirmed empirically with a standalone probe (zero physical
/// keys held): posting a "T" keyDown/keyUp with `.flags = .maskCommand` (the
/// shape `sendKeyboardShortcut` uses for e.g. Cmd+T) makes
/// `CGEventSource.keyState(.hidSystemState, key: 0x37)` report Command as
/// down immediately afterward, with NO corresponding real hardware event —
/// and it stays stuck "down" until something else corrects it (in the wild,
/// this self-corrects within ~20-60ms once a genuinely-held key generates
/// its own real hardware event, but that's a race, not a guarantee — the
/// probe showed it never self-correct at all when no other key was held).
/// The same probe confirmed this happens identically whether the event is
/// posted via `.cghidEventTap`, `.cgSessionEventTap`, or `postToPid` — it's
/// not about tap level or targeting, any posted `.flags` writes through to
/// the shared HID key-state table for exactly the bits that were set.
///
/// The fix is not to filter or re-poll around the bad reading (that leaves
/// the real defect in place and only narrows the race) — it's to undo the
/// specific side effect immediately: post a real keyUp for exactly the
/// modifier keycode(s) that were in `flags`, with `flags = []`, which the
/// same probe confirmed clears the contaminated keyState back to accurate
/// and keeps it there. Deliberately scoped to ONLY the bits present in
/// `flags` — unlike `releaseAllModifierKeys()`, this must NOT touch
/// modifiers outside that set, since one of them (e.g. the gesture's own
/// trigger combo) may be genuinely, physically held right now, and clearing
/// it would just trade a false "still held" for a false "released".
func clearModifierStateContamination(from flags: CGEventFlags) {
    guard let source = CGEventSource(stateID: .privateState) else { return }
    let modifierKeyCodes: [(CGEventFlags, CGKeyCode, CGKeyCode)] = [
        (.maskCommand, 0x37, 0x36),
        (.maskShift, 0x38, 0x3C),
        (.maskAlternate, 0x3A, 0x3D),
        (.maskControl, 0x3B, 0x3E)
    ]
    for (mask, left, right) in modifierKeyCodes where flags.contains(mask) {
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: left, keyDown: false) {
            keyUp.flags = []; keyUp.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: right, keyDown: false) {
            keyUp.flags = []; keyUp.post(tap: .cghidEventTap)
        }
    }
}

/// Tracks modifier bits that this app's OWN in-flight `sendKeyboardShortcut`
/// calls are known to be about to write into the shared HID key-state table
/// (see `clearModifierStateContamination`), so `NSEvent.ModifierFlags
/// .currentHardware` can exclude them immediately — a plain in-memory check,
/// not another CGEvent round-trip. `clearModifierStateContamination` also
/// posts a real corrective keyUp, which is the actual fix (it makes the
/// OS-level state correct for every OTHER process too, not just this one) —
/// but that correction has real, non-zero latency to land. This closes the
/// gap between "we posted something that will corrupt this bit" and "the
/// correction has actually taken effect," for OUR OWN reads specifically.
///
/// This is bookkeeping about a fully-understood, self-caused, precisely-
/// scoped operation `sendKeyboardShortcut` knows about *before* it posts
/// anything — not a retry loop compensating for an unreliable read.
/// Ref-counted so overlapping shortcuts (e.g. a bundle firing several in a
/// row) don't have one's cleanup prematurely un-suppress bits another is
/// still relying on.
final class SyntheticModifierSuppression {
    static let shared = SyntheticModifierSuppression()
    private init() {}

    private let lock = NSLock()
    private var suppressedBits: CGEventFlags = []
    private var activeCount = 0

    /// Call immediately before posting a shortcut with these flags.
    func begin(_ flags: CGEventFlags) {
        lock.lock()
        suppressedBits.formUnion(flags)
        activeCount += 1
        lock.unlock()
    }

    /// Call once the shortcut's posting AND corrective cleanup are both done.
    func end(_ flags: CGEventFlags) {
        lock.lock()
        activeCount = max(0, activeCount - 1)
        if activeCount == 0 {
            suppressedBits = []
        }
        lock.unlock()
    }

    var currentlySuppressed: NSEvent.ModifierFlags {
        lock.lock()
        let bits = suppressedBits
        lock.unlock()
        return NSEvent.ModifierFlags(rawValue: UInt(bits.rawValue)).normalized
    }
}

// MARK: - Modifier Release Waiting

/// Check whether ANY modifier key is currently held using multiple state sources.
/// Returns `true` if at least one modifier is detected as held by any source.
private func anyModifierHeld() -> Bool {
    // CGEventFlags mask for the four standard modifiers
    let cgBits: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    // NSEvent mask for the same
    let nsBits: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    // Check all three state sources — if ANY reports a modifier held, return true.
    // .hidSystemState: hardware-level state
    // .combinedSessionState: merged hardware + synthetic state
    // NSEvent.modifierFlags: AppKit's view of modifier state
    let hid = CGEventSource.flagsState(.hidSystemState).intersection(cgBits)
    if !hid.isEmpty { return true }

    let combined = CGEventSource.flagsState(.combinedSessionState).intersection(cgBits)
    if !combined.isEmpty { return true }

    let appkit = NSEvent.modifierFlags.intersection(nsBits)
    if !appkit.isEmpty { return true }

    return false
}

/// Wait until ALL physical modifier keys are released, or until timeout.
/// Queries three independent state sources (HID, combined session, AppKit)
/// and requires ALL of them to report no modifiers held.
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
        if !anyModifierHeld() {
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
