// swiftlint:disable all  — dense table-driven cases ported from the plugins' scratch tests
import XCTest
import CoreGraphics

final class RecognizersTests: XCTestCase {
    private func eq<T: Equatable>(_ a: T, _ b: T, _ n: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, n, file: file, line: line)
    }

    func testShapesAndShakes() {
        func circle(r: CGFloat, ccw: Bool, turns: Double = 1.15, n: Int = 60) -> [CGPoint] {
            (0...Int(Double(n) * turns)).map { i in let a = 2 * Double.pi * Double(i) / Double(n) * (ccw ? 1 : -1); return CGPoint(x: 900 + r * cos(a), y: 600 + r * sin(a)) }
        }
        func zig(amp: CGFloat, strokes: Int, vertical: Bool, lead: CGFloat = 0) -> [CGPoint] {
            var pts: [CGPoint] = []; var pos: CGFloat = lead
            for s in 0..<strokes { let target: CGFloat = s % 2 == 0 ? amp : -amp
                let steps = 8; let from = pos
                for k in 1...steps { pos = from + (target - from) * CGFloat(k) / CGFloat(steps); pts.append(vertical ? CGPoint(x: 900, y: 600 + pos) : CGPoint(x: 900 + pos, y: 600)) } }
            return pts
        }
        eq(Recognizers.circle(circle(r: 100, ccw: true), minSize: 90), "circle_ccw", "ccw")
        eq(Recognizers.circle(circle(r: 100, ccw: false), minSize: 90), "circle_cw", "cw")
        eq(Recognizers.circle(circle(r: 60, ccw: false), minSize: 90), "circle_cw", "r=60 passes") 
        eq(Recognizers.circle(circle(r: 40, ccw: false), minSize: 90), nil, "small")
        eq(Recognizers.circle(circle(r: 100, ccw: false, turns: 0.5), minSize: 90), nil, "half circle")
        eq(Recognizers.circle(zig(amp: 100, strokes: 8, vertical: false), minSize: 90), nil, "zigzag not circle")
        eq(Recognizers.shake(zig(amp: 70, strokes: 7, vertical: false), vertical: false, reversalsNeeded: 4, minStroke: 70), true, "h shake")
        eq(Recognizers.shake(zig(amp: 70, strokes: 7, vertical: false), vertical: true, reversalsNeeded: 4, minStroke: 70), false, "h shake not v")
        eq(Recognizers.shake(zig(amp: 70, strokes: 7, vertical: true), vertical: true, reversalsNeeded: 4, minStroke: 70), true, "v shake")
        eq(Recognizers.shake(zig(amp: 70, strokes: 7, vertical: true, lead: 30), vertical: true, reversalsNeeded: 4, minStroke: 70), true, "v shake with lead-in")
        eq(Recognizers.shake(zig(amp: 20, strokes: 12, vertical: false), vertical: false, reversalsNeeded: 4, minStroke: 70), false, "jitter ignored")
        eq(Recognizers.shake(zig(amp: 70, strokes: 3, vertical: false), vertical: false, reversalsNeeded: 4, minStroke: 70), false, "too few")
        eq(Recognizers.shake(circle(r: 100, ccw: true, turns: 3), vertical: false, reversalsNeeded: 4, minStroke: 70), false, "circles aren't shakes")
        let wander = (0..<200).map { i in CGPoint(x: 900 + 20 * sin(Double(i) / 9), y: 600 + 15 * cos(Double(i) / 13)) }
        eq(Recognizers.shake(wander, vertical: false, reversalsNeeded: 4, minStroke: 70), false, "wander h"); eq(Recognizers.circle(wander, minSize: 90), nil, "wander circle")

    }
}
