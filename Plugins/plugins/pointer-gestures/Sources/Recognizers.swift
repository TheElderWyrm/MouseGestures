import Foundation
import CoreGraphics

/// Pure shape recognition over a list of pointer positions (oldest first). Coordinates are y-up (Cocoa).
enum Recognizers {

    /// Counts full back-and-forth swings along one axis. A swing counts once the pointer has travelled
    /// at least `minStroke` against the previous direction; leading partial strokes and jitter are ignored.
    static func shake(_ pts: [CGPoint], vertical: Bool, reversalsNeeded: Int, minStroke: CGFloat) -> Bool {
        guard pts.count >= 6 else { return false }
        func v(_ p: CGPoint) -> CGFloat { vertical ? p.y : p.x }
        var ext = v(pts[0]), dir = 0, reversals = 0
        for p in pts.dropFirst() {
            let d = v(p) - ext
            if dir == 0 { if abs(d) >= minStroke { dir = d > 0 ? 1 : -1; ext = v(p) } }
            else if (d > 0 ? 1 : -1) == dir { ext = v(p) }
            else if abs(d) >= minStroke { reversals += 1; dir = -dir; ext = v(p) }
        }
        guard reversals >= reversalsNeeded else { return false }
        let xs = pts.map { $0.x }, ys = pts.map { $0.y }
        let w = xs.max()! - xs.min()!, h = ys.max()! - ys.min()!
        return vertical ? w <= h * 0.6 : h <= w * 0.6
    }

    /// "circle_ccw" / "circle_cw" when the tail of `pts` closes a loop, else nil. Uses the cumulative
    /// turning angle: a loop turns about 360° one way, a zigzag turns back and forth and cancels out.
    static func circle(_ pts: [CGPoint], minSize: CGFloat) -> String? {
        guard pts.count >= 8 else { return nil }
        var turn = [CGFloat](repeating: 0, count: pts.count)
        for i in 1..<(pts.count - 1) {
            let a = CGPoint(x: pts[i].x - pts[i-1].x, y: pts[i].y - pts[i-1].y)
            let b = CGPoint(x: pts[i+1].x - pts[i].x, y: pts[i+1].y - pts[i].y)
            turn[i] = atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
        }
        var sum: CGFloat = 0, absSum: CGFloat = 0
        var i = pts.count - 2
        while i >= 1 {
            sum += turn[i]; absSum += abs(turn[i])
            if abs(sum) >= 2 * .pi * 0.92 {
                let seg = Array(pts[(i - 1)...])
                let xs = seg.map { $0.x }, ys = seg.map { $0.y }
                let w = xs.max()! - xs.min()!, h = ys.max()! - ys.min()!
                guard w >= minSize, h >= minSize, max(w, h) / min(w, h) <= 2, absSum <= abs(sum) * 1.4 else { return nil }
                var len: CGFloat = 0
                for k in 1..<seg.count { len += hypot(seg[k].x - seg[k-1].x, seg[k].y - seg[k-1].y) }
                let ratio = len / (.pi * (w + h) / 2)
                guard ratio > 0.7, ratio < 1.8 else { return nil }
                return sum > 0 ? "circle_ccw" : "circle_cw"
            }
            i -= 1
        }
        return nil
    }
}
