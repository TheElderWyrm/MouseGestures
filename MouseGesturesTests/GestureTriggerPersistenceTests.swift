import XCTest
import Cocoa

/// Regression tests for the keyboard-shortcut / mouse-button trigger MODIFIER
/// persistence bug (`Core/GenericActivation.swift`).
///
/// `GenericActivation` persists a trigger's modifier flags inside `AnyCodable`.
/// It used to store `NSEvent.ModifierFlags.rawValue`, which is a `UInt` — but
/// `AnyCodable.encode(to:)` has no `UInt` case, so the value fell through to
/// `encodeNil()` (written as JSON `null`); and even if it hadn't, a JSON number
/// decodes back as `Int`, which the old read (`config["modifiers"]?.value as?
/// UInt`) can't bridge. Either way the read returned `nil`, which nulled the
/// ENTIRE keyboard/mouse-button trigger — so every keyboard-shortcut and
/// mouse-button gesture silently stopped firing after an app restart.
///
/// The fix stores the rawValue as `Int` (which AnyCodable encodes) and reads it
/// back through a tolerant coercion (`decodeModifierRaw`, mirrored below — same
/// coercion-recipe pattern as `ActionParametersTests`, since this no-host logic
/// target does not link `GenericActivation` itself) that accepts
/// Int/UInt/NSNumber. These tests pin both the root cause and the fix.
final class GestureTriggerModifierPersistenceTests: XCTestCase {

    /// Mirror of the fileprivate `decodeModifierRaw(_:)` in GenericActivation.swift.
    private func decodeModifierRaw(_ value: Any?) -> UInt? {
        if let u = value as? UInt { return u }
        if let i = value as? Int { return UInt(bitPattern: i) }
        if let n = value as? NSNumber { return n.uintValue }
        return nil
    }

    private func jsonRoundTrip(_ box: AnyCodable) -> AnyCodable {
        let data = try! JSONEncoder().encode(box)
        return try! JSONDecoder().decode(AnyCodable.self, from: data)
    }

    /// THE FIX: storing the rawValue as Int survives a JSON round-trip and
    /// coerces back to the exact same ModifierFlags, for every combo.
    func testModifierFlagsStoredAsIntSurviveRoundTrip() {
        let combos: [NSEvent.ModifierFlags] = [
            [], [.command], [.command, .option], [.command, .shift],
            [.control, .option], [.command, .control, .option, .shift]
        ]
        for flags in combos {
            let stored = AnyCodable(Int(flags.rawValue))                 // how the fix persists it
            let restored = decodeModifierRaw(jsonRoundTrip(stored).value)
            XCTAssertEqual(restored, flags.rawValue,
                           "ModifierFlags \(flags.rawValue) must survive Int persistence + JSON round-trip")
            XCTAssertEqual(restored.map { NSEvent.ModifierFlags(rawValue: $0) }, flags)
        }
    }

    /// The coercion accepts every numeric boxing that can reach it (Int after a
    /// JSON round-trip, an in-memory UInt, NSNumber) and rejects non-numerics.
    func testDecodeModifierRawAcceptsAllNumericBoxings() {
        let raw = NSEvent.ModifierFlags([.command, .option]).rawValue
        XCTAssertEqual(decodeModifierRaw(Int(raw)), raw)
        XCTAssertEqual(decodeModifierRaw(UInt(raw)), raw)
        XCTAssertEqual(decodeModifierRaw(NSNumber(value: raw)), raw)
        XCTAssertNil(decodeModifierRaw(nil))
        XCTAssertNil(decodeModifierRaw("⌘⌥"))
    }

    /// End-to-end shape of the bug: a full keyboard-trigger detection-config dict
    /// (as GenericActivation stores it) round-trips with modifiers intact.
    func testKeyboardTriggerConfigDictRoundTripPreservesModifiers() {
        let modifiers = NSEvent.ModifierFlags([.command, .shift]).rawValue
        let config: [String: AnyCodable] = [
            "keyCode": AnyCodable(Int(48)),                    // Tab
            "modifiers": AnyCodable(Int(modifiers)),
            "displayString": AnyCodable("⌘⇧⇥")
        ]
        let data = try! JSONEncoder().encode(config)
        let decoded = try! JSONDecoder().decode([String: AnyCodable].self, from: data)

        XCTAssertEqual(decoded["keyCode"]?.value as? Int, 48)
        XCTAssertEqual(decodeModifierRaw(decoded["modifiers"]?.value), modifiers,
                       "modifiers must NOT decode to nil (the bug nulled the whole trigger)")
        XCTAssertEqual(decoded["displayString"]?.value as? String, "⌘⇧⇥")
    }

    /// ROOT CAUSE: the OLD path stored a bare `UInt` in AnyCodable, which drops
    /// it to `null` at ENCODE time — so the modifier value is destroyed on save,
    /// not merely mis-read on load. Once round-tripped it is unrecoverable even
    /// by the tolerant coercion (there is nothing left to coerce). This is why
    /// the fix needs BOTH halves: store as Int going forward, AND fall back to
    /// the `components` copy in Gesture.swift to repair already-corrupted configs
    /// (the genericActivation value itself is gone).
    func testOldUIntStorageIsUnrecoverable_rootCause() {
        let raw = NSEvent.ModifierFlags.command.rawValue   // a UInt
        let restored = jsonRoundTrip(AnyCodable(raw))      // old storage: AnyCodable(UInt)
        XCTAssertNil(restored.value as? UInt,
                     "old `as? UInt` read fails after a round-trip")
        XCTAssertNil(decodeModifierRaw(restored.value),
                     "a UInt-stored modifier is dropped to null on encode and is unrecoverable — must repair from components")
    }
}
