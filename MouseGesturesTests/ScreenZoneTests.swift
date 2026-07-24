import XCTest
import Cocoa

/// Geometry smoke tests for `ScreenZone.contains(point:screenFrame:)` — the pure
/// hit-testing that decides which edge/corner a cursor is in. Uses a fixed
/// 1000x800 frame so the expected rectangles are easy to reason about.
final class ScreenZoneTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)

    func testAllZonesEnumerated() {
        XCTAssertEqual(ScreenZone.allCases.count, 8)
        XCTAssertEqual(ScreenZone.topLeft.rawValue, "Top Left Corner")
        XCTAssertEqual(ScreenZone.topLeft.displayName, ScreenZone.topLeft.rawValue)
    }

    func testTopLeftCornerHitTest() {
        // Default cornerSize 30 -> rect x[0,30), y[770,800).
        XCTAssertTrue(ScreenZone.topLeft.contains(point: NSPoint(x: 5, y: 790), screenFrame: screen))
        XCTAssertFalse(ScreenZone.topLeft.contains(point: NSPoint(x: 500, y: 400), screenFrame: screen))
    }

    func testBottomLeftCornerHitTest() {
        // rect x[0,30), y[0,30).
        XCTAssertTrue(ScreenZone.bottomLeft.contains(point: NSPoint(x: 10, y: 10), screenFrame: screen))
        XCTAssertFalse(ScreenZone.bottomLeft.contains(point: NSPoint(x: 10, y: 200), screenFrame: screen))
    }

    func testTopEdgeExcludesCorners() {
        // Top edge spans x[30,970), y[770,800) — corner columns are excluded.
        XCTAssertTrue(ScreenZone.top.contains(point: NSPoint(x: 500, y: 790), screenFrame: screen))
        XCTAssertFalse(ScreenZone.top.contains(point: NSPoint(x: 5, y: 790), screenFrame: screen))
    }

    // MARK: - SyntheticModifierSuppression (Chromium synthetic-modifier fix)
    //
    // `Utilities/Extensions.swift` (where the real `SyntheticModifierSuppression`
    // and `NSEvent.ModifierFlags.normalized` live) is not linked into this
    // no-host logic target. `CGEventFlags`/`NSEvent.ModifierFlags` themselves
    // are plain Cocoa/CoreGraphics types (already reachable via `import
    // Cocoa` above), so this mirrors just the app-defined ref-counting +
    // normalization logic locally (same coercion-recipe pattern as
    // ActionParametersTests.swift) to keep it regression-tested.
    private final class SyntheticModifierSuppressionMirror {
        private let lock = NSLock()
        private var suppressedBits: CGEventFlags = []
        private var activeCount = 0

        func begin(_ flags: CGEventFlags) {
            lock.lock()
            suppressedBits.formUnion(flags)
            activeCount += 1
            lock.unlock()
        }

        func end(_ flags: CGEventFlags) {
            lock.lock()
            activeCount = max(0, activeCount - 1)
            if activeCount == 0 { suppressedBits = [] }
            lock.unlock()
        }

        var currentlySuppressed: NSEvent.ModifierFlags {
            lock.lock()
            let bits = suppressedBits
            lock.unlock()
            var n: NSEvent.ModifierFlags = []
            let raw = NSEvent.ModifierFlags(rawValue: UInt(bits.rawValue))
            if raw.contains(.command) { n.insert(.command) }
            if raw.contains(.control) { n.insert(.control) }
            if raw.contains(.option) { n.insert(.option) }
            if raw.contains(.shift) { n.insert(.shift) }
            return n
        }
    }

    /// Two invariants must hold: (1) the `CGEventFlags` → `NSEvent.ModifierFlags`
    /// bit reinterpretation in `currentlySuppressed` must be correct for the
    /// four standard modifiers (they happen to share bit positions, and
    /// normalization must strip any stray device bits); (2) overlapping
    /// begin/end pairs must ref-count so one shortcut's cleanup can't
    /// prematurely un-suppress bits another shortcut is still relying on.
    func testSyntheticModifierSuppressionRefCountingAndBitMapping() {
        let s = SyntheticModifierSuppressionMirror()
        XCTAssertTrue(s.currentlySuppressed.isEmpty, "precondition: nothing suppressed")

        s.begin(.maskCommand)
        XCTAssertTrue(s.currentlySuppressed.contains(.command),
                      "CGEventFlags.maskCommand must reinterpret to NSEvent .command")
        XCTAssertFalse(s.currentlySuppressed.contains(.shift))

        // Overlap with a second shortcut carrying a different flag.
        s.begin(.maskShift)
        XCTAssertTrue(s.currentlySuppressed.contains(.command))
        XCTAssertTrue(s.currentlySuppressed.contains(.shift))

        // Ending the first must NOT drop bits while the second is still active.
        s.end(.maskCommand)
        XCTAssertTrue(s.currentlySuppressed.contains(.command),
                      "bits must persist until the ref count reaches zero")
        XCTAssertTrue(s.currentlySuppressed.contains(.shift))

        // Ending the last clears everything.
        s.end(.maskShift)
        XCTAssertTrue(s.currentlySuppressed.isEmpty, "all bits cleared when ref count hits zero")

        // Only the four user modifiers survive normalization.
        s.begin([.maskControl, .maskAlternate])
        XCTAssertEqual(s.currentlySuppressed, [.control, .option])
        s.end([.maskControl, .maskAlternate])
        XCTAssertTrue(s.currentlySuppressed.isEmpty)
    }

    // MARK: - DragModifier <-> MouseButton conversions
    //
    // Neither `Detection/DragModifier.swift` nor the
    // `ActionPlugins/.../MouseButtonTrigger.MouseButton` type it converts to
    // is linked into this no-host logic target, so both are mirrored locally
    // (same pattern as ActionParametersTests.swift's coercion-recipe copy)
    // to keep the conversion table regression-tested.
    private enum MouseButtonMirror: Equatable {
        case none, any, left, right, middle, button4, button5
    }

    private enum DragModifierMirror: Equatable {
        case none, anyDrag, leftDrag, rightDrag, middleDrag

        static func from(mouseButton: MouseButtonMirror) -> DragModifierMirror {
            switch mouseButton {
            case .none, .any: return .none
            case .left: return .leftDrag
            case .right: return .rightDrag
            case .middle: return .middleDrag
            case .button4, .button5: return .none
            }
        }

        var correspondingMouseButton: MouseButtonMirror? {
            switch self {
            case .none, .anyDrag: return nil
            case .leftDrag:  return .left
            case .rightDrag: return .right
            case .middleDrag: return .middle
            }
        }
    }

    func testDragModifierMouseButtonRoundTrip() {
        XCTAssertEqual(DragModifierMirror.from(mouseButton: .left), .leftDrag)
        XCTAssertEqual(DragModifierMirror.from(mouseButton: .right), .rightDrag)
        XCTAssertEqual(DragModifierMirror.from(mouseButton: .middle), .middleDrag)
        // "Any Button", extended buttons and "None" have no 1:1 drag mapping.
        XCTAssertEqual(DragModifierMirror.from(mouseButton: .any), .none)
        XCTAssertEqual(DragModifierMirror.from(mouseButton: .button4), .none)
        XCTAssertEqual(DragModifierMirror.from(mouseButton: .button5), .none)
        XCTAssertEqual(DragModifierMirror.from(mouseButton: .none), .none)

        XCTAssertEqual(DragModifierMirror.leftDrag.correspondingMouseButton, .left)
        XCTAssertEqual(DragModifierMirror.rightDrag.correspondingMouseButton, .right)
        XCTAssertEqual(DragModifierMirror.middleDrag.correspondingMouseButton, .middle)
        XCTAssertNil(DragModifierMirror.anyDrag.correspondingMouseButton)
        XCTAssertNil(DragModifierMirror.none.correspondingMouseButton)
    }
}
