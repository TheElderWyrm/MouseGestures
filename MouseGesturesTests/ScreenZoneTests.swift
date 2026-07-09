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
}
