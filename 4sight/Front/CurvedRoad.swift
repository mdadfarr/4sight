import SwiftUI

/// Live mode: the road drawn along where the bike has actually been, and where the
/// route says it is going, instead of a straight strip.
///
/// Tracks are not moved onto it. The rear camera is bolted to the bike, so a car on a
/// bend behind is already reported at its true bike-frame position, which is on this
/// curve; sliding it along the trail would bend it twice.
enum CurvedRoad {
    /// Under this much usable trail there is nothing to trust: indoors, no fix yet, or
    /// just set off. The caller then draws the straight road exactly as before.
    static let minTrail = 10.0

    /// A centreline from far behind, through the rider at `rider`, to far ahead.
    struct Line {
        let points: [(Double, Double)]
        let rider: Int
    }

    static func centerline(_ route: LiveRoute, at t: Double) -> Line? {
        let behind = route.trailLine(at: t)
        guard length(behind) >= minTrail else { return nil }
        let back = extended(smoothed(behind), by: 40)
        let ahead = route.line(at: t)
        let forward = ahead.count > 1 ? ahead : [(0, 0), (0, World.zFar)]
        return Line(points: Array(back.reversed()) + forward.dropFirst(), rider: back.count - 1)
    }

    static func draw(_ ctx: inout GraphicsContext, _ line: Line, travelled: Double) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: Design.width, height: Design.height)),
                 with: .color(Palette.ground))
        let pts = line.points, n = normals(pts)
        ctx.fill(band(pts, n, Road.farEdge, Road.kerb), with: .color(Palette.road))

        let lane = GraphicsContext.Shading.color(Palette.lane)
        for x in [Road.kerb, Road.farEdge] {
            ctx.fill(band(pts, n, x - 0.06, x + 0.06), with: lane)
        }

        // Dashes keyed to distance ridden, as on the straight road: still when stopped.
        let cum = cumulative(pts), origin = cum[line.rider]
        let shift = travelled.truncatingRemainder(dividingBy: 7)
        for x in Road.dividers {
            var w = -80.0
            while w < 300 {
                let s1 = shift - w, s0 = s1 - 3                // metres behind the rider
                if let a = at(origin - s0, pts, n, cum), let b = at(origin - s1, pts, n, cum) {
                    ctx.fill(SceneRenderer.poly([
                        Camera.pt(a.x + a.nx * (x - 0.085), a.z + a.nz * (x - 0.085)),
                        Camera.pt(a.x + a.nx * (x + 0.085), a.z + a.nz * (x + 0.085)),
                        Camera.pt(b.x + b.nx * (x + 0.085), b.z + b.nz * (x + 0.085)),
                        Camera.pt(b.x + b.nx * (x - 0.085), b.z + b.nz * (x - 0.085)),
                    ]), with: lane)
                }
                w += 7
            }
        }

        // The camera's wedge is bolted to the bike, so it stays straight behind.
        let cone = SceneRenderer.conePath()
        ctx.fill(cone, with: .color(Palette.coneTint))
        ctx.stroke(cone, with: .color(Palette.cone), lineWidth: 1.5)
    }

    // MARK: - Geometry

    static func length(_ p: [(Double, Double)]) -> Double {
        zip(p, p.dropFirst()).reduce(0) { $0 + hypot($1.1.0 - $1.0.0, $1.1.1 - $1.0.1) }
    }

    /// Two passes of a 1-2-1 average: GPS wanders a few metres fix to fix, and the road
    /// should not. Endpoints stay put so the trail still starts under the puck.
    static func smoothed(_ p: [(Double, Double)]) -> [(Double, Double)] {
        guard p.count > 2 else { return p }
        var q = p
        for _ in 0..<2 {
            let r = q
            for i in 1..<(r.count - 1) {
                q[i] = ((r[i - 1].0 + 2 * r[i].0 + r[i + 1].0) / 4,
                        (r[i - 1].1 + 2 * r[i].1 + r[i + 1].1) / 4)
            }
        }
        return q
    }

    /// Carries the far end on along its last direction, so the road does not stop where
    /// the remembered trail does.
    static func extended(_ p: [(Double, Double)], by d: Double) -> [(Double, Double)] {
        guard p.count > 1 else { return p }
        let a = p[p.count - 2], b = p[p.count - 1]
        let len = max(hypot(b.0 - a.0, b.1 - a.1), 0.0001)
        return p + [(b.0 + (b.0 - a.0) / len * d, b.1 + (b.1 - a.1) / len * d)]
    }

    /// Unit normal to the right of travel at each point; travel runs toward higher index.
    static func normals(_ p: [(Double, Double)]) -> [(Double, Double)] {
        p.indices.map { i in
            let a = p[max(i - 1, 0)], b = p[min(i + 1, p.count - 1)]
            let dx = b.0 - a.0, dz = b.1 - a.1
            let len = max(hypot(dx, dz), 0.0001)
            return (-dz / len, dx / len)
        }
    }

    static func cumulative(_ p: [(Double, Double)]) -> [Double] {
        var out = [0.0]
        for i in 1..<max(p.count, 1) {
            out.append(out[i - 1] + hypot(p[i].0 - p[i - 1].0, p[i].1 - p[i - 1].1))
        }
        return out
    }

    /// The centreline point and normal at arc length `s` from the far-behind end.
    static func at(_ s: Double, _ p: [(Double, Double)], _ n: [(Double, Double)],
                   _ cum: [Double]) -> (x: Double, z: Double, nx: Double, nz: Double)? {
        guard let last = cum.last, s >= 0, s <= last, p.count > 1 else { return nil }
        let i = max(1, cum.firstIndex { $0 >= s } ?? cum.count - 1)
        let span = max(cum[i] - cum[i - 1], 0.0001), f = (s - cum[i - 1]) / span
        return (p[i - 1].0 + (p[i].0 - p[i - 1].0) * f, p[i - 1].1 + (p[i].1 - p[i - 1].1) * f,
                n[i - 1].0 + (n[i].0 - n[i - 1].0) * f, n[i - 1].1 + (n[i].1 - n[i - 1].1) * f)
    }

    /// The strip between two offsets right of the centreline, clipped to the drawable
    /// range so points behind the camera never reach the projection.
    static func band(_ p: [(Double, Double)], _ n: [(Double, Double)], _ a: Double, _ b: Double) -> Path {
        let keep = p.indices.filter { p[$0].1 >= World.zFar && p[$0].1 <= World.zNear }
        let left = keep.map { Camera.pt(p[$0].0 + n[$0].0 * a, p[$0].1 + n[$0].1 * a) }
        let right = keep.reversed().map { Camera.pt(p[$0].0 + n[$0].0 * b, p[$0].1 + n[$0].1 * b) }
        return SceneRenderer.poly(left + right)
    }
}
