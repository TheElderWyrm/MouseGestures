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

// MARK: - Modifier Masking via CGEvent Tap

/// Temporarily masks physical modifier keys by installing a CGEvent tap that
/// strips modifier flags from `flagsChanged` events at the HID level.
/// This makes the system "forget" about held physical modifiers so that
/// AppleScript/System Events keyboard sends arrive with a clean state.
///
/// IMPORTANT: The event tap callback runs on the run loop where the tap source
/// is registered. The caller must ensure that run loop is spinning. The
/// `withCleanModifiers` method handles this by running the tap on the
/// calling thread's run loop and spinning it manually.
///
/// Usage:
///     ModifierMask.withCleanModifiers {
///         // AppleScript or other code that needs no physical modifiers
///     }
class ModifierMask {
    
    /// The C callback for the event tap. Strips all modifier flags from flagsChanged events.
    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        // If the tap is disabled by the system (e.g. timeout), re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let refcon = refcon {
                let tapPtr = Unmanaged<TapState>.fromOpaque(refcon).takeUnretainedValue()
                if let tap = tapPtr.machPort {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }
        // Strip all modifier key flags so the system sees no modifiers held
        event.flags = []
        return Unmanaged.passUnretained(event)
    }
    
    /// Mutable state passed to the tap callback via refcon.
    private class TapState {
        var machPort: CFMachPort?
    }
    
    /// Execute a closure with all physical modifier keys masked.
    /// Installs a HID-level event tap that strips modifier flags, executes
    /// the closure, then removes the tap.
    ///
    /// The tap callback is processed on the CURRENT thread's run loop, which
    /// is spun manually. This avoids the deadlock that occurs when the main
    /// thread is blocked (e.g. by a semaphore in the sandbox).
    static func withCleanModifiers(_ body: () -> Void) {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        
        // TapState lets the callback re-enable the tap if the system disables it.
        let state = TapState()
        let statePtr = Unmanaged.passRetained(state)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: statePtr.toOpaque()
        ) else {
            statePtr.release()
            // Tap creation failed (no accessibility?), run body anyway
            body()
            return
        }
        state.machPort = tap
        
        guard let rlSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            statePtr.release()
            body()
            return
        }
        
        // Add tap to the CURRENT thread's run loop (not main, which may be blocked).
        let rl = CFRunLoopGetCurrent()
        CFRunLoopAddSource(rl, rlSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        // Spin the run loop briefly to let the tap start processing events.
        // This ensures the system picks up the tap before we proceed.
        CFRunLoopRunInMode(.defaultMode, 0.01, false)
        
        // Post a clean flagsChanged event to flush the current modifier state.
        // This event will be intercepted by our tap, which strips its flags,
        // making the system see "no modifiers held".
        if let src = CGEventSource(stateID: .hidSystemState),
           let cleanFlags = CGEvent(source: src) {
            cleanFlags.type = .flagsChanged
            cleanFlags.flags = []
            cleanFlags.post(tap: .cghidEventTap)
        }
        
        // Spin again to process the clean flagsChanged through the tap.
        CFRunLoopRunInMode(.defaultMode, 0.05, false)
        
        // Execute the action.
        body()
        
        // Spin briefly to process any residual events before removing the tap.
        CFRunLoopRunInMode(.defaultMode, 0.05, false)
        
        // Remove the tap, restoring normal modifier handling.
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(rl, rlSource, .commonModes)
        statePtr.release()
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
