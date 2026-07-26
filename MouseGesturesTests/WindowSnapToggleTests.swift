import XCTest
import Cocoa

/// Regression tests for the window snap-to-region TOGGLE-BACK decision
/// (`WindowManagementPlugin.snapWindow`).
///
/// Snapping the same position twice in a row is meant to undo the first snap
/// (restore the pre-snap frame). The bug: it toggled back on a POSITION MATCH
/// ALONE, without checking the window was still at the snapped frame — so
/// "snap → move the window yourself → snap the same position again" wrongly
/// restored the old frame instead of snapping to the set position. The fix
/// additionally requires the window to still be (approximately) at the frame the
/// snap left it at.
///
/// The decision + tolerance are mirrored here (same coercion-recipe pattern as
/// `ActionParametersTests`) since `WindowManagementPlugin` is not linked into
/// this no-host logic target and its real path needs the Accessibility API.
final class WindowSnapToggleTests: XCTestCase {

    /// Mirror of `WindowManagementPlugin.framesApproximatelyEqual`.
    private func framesApproximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 8) -> Bool {
        return abs(a.origin.x - b.origin.x) <= tolerance &&
               abs(a.origin.y - b.origin.y) <= tolerance &&
               abs(a.size.width - b.size.width) <= tolerance &&
               abs(a.size.height - b.size.height) <= tolerance
    }

    private struct SnapRecord { let position: String; let originalFrame: CGRect; let snappedFrame: CGRect }

    /// Mirror of the FIXED toggle-back decision in `snapWindow`: revert to the
    /// pre-snap frame ONLY when the same position is repeated AND the window is
    /// still (approximately) at the frame the last snap produced.
    private func shouldRevert(previous: SnapRecord?, position: String, currentFrame: CGRect) -> Bool {
        guard let previous = previous, previous.position == position else { return false }
        return framesApproximatelyEqual(currentFrame, previous.snappedFrame)
    }

    private let snapped = CGRect(x: 0, y: 0, width: 800, height: 1000)     // e.g. left_half
    private let preSnap = CGRect(x: 300, y: 200, width: 640, height: 480)

    func testRevertsWhenWindowStillAtSnappedPosition() {
        let rec = SnapRecord(position: "left_half", originalFrame: preSnap, snappedFrame: snapped)
        // Same position, window has not moved (within tolerance) -> toggle back.
        XCTAssertTrue(shouldRevert(previous: rec, position: "left_half",
                                   currentFrame: CGRect(x: 2, y: 1, width: 800, height: 1000)))
    }

    func testDoesNotRevertAfterUserMovedWindow() {
        // THE REPORTED BUG: snap, then move the window yourself, then snap the
        // same position again -> must snap to the set position, NOT restore the
        // old frame.
        let rec = SnapRecord(position: "left_half", originalFrame: preSnap, snappedFrame: snapped)
        let movedAway = CGRect(x: 450, y: 380, width: 720, height: 560)
        XCTAssertFalse(shouldRevert(previous: rec, position: "left_half", currentFrame: movedAway))
    }

    func testDoesNotRevertForDifferentPosition() {
        let rec = SnapRecord(position: "left_half", originalFrame: preSnap, snappedFrame: snapped)
        XCTAssertFalse(shouldRevert(previous: rec, position: "right_half", currentFrame: snapped))
    }

    func testDoesNotRevertWithNoPreviousSnap() {
        XCTAssertFalse(shouldRevert(previous: nil, position: "left_half", currentFrame: snapped))
    }

    func testToleranceBoundaries() {
        let base = CGRect(x: 100, y: 100, width: 500, height: 400)
        XCTAssertTrue(framesApproximatelyEqual(base, base.offsetBy(dx: 8, dy: 0)))    // exactly at tolerance
        XCTAssertFalse(framesApproximatelyEqual(base, base.offsetBy(dx: 9, dy: 0)))   // just beyond
        XCTAssertFalse(framesApproximatelyEqual(base, CGRect(x: 100, y: 100, width: 520, height: 400))) // width +20
    }
}
