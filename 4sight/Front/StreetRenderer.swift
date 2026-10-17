import CoreLocation
import SwiftUI

/// The live map, Tesla style: the real streets from `StreetMap` drawn through the same
/// follow camera as the scripted demo, so roads have their true width and lane count,
/// sidewalks and crossings show where the rider actually is, and the rear camera's
/// tracks sit on that ground at their measured distance.
///
/// Heading-up: the rider is always at (0, 0) facing up the screen and the world turns.
enum StreetRenderer {
    /// Clip window in the rider frame (z behind). Past `ahead` the haze covers it; past
    /// `behind` it is under the bottom bar. Nothing reaches the camera at z = +8.
    static let ahead = -260.0, behind = 50.0, side = 220.0
    static let radius = 320.0

    static func draw(_ ctx: inout GraphicsContext, map: StreetMap?, rider: CLLocationCoordinate2D?,
                     heading h: Double, route: [CLLocationCoordinate2D]) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: Design.width, height: Design.height)),
                 with: .color(Palette.liveGround))
        guard let rider else { return }
        if let map {
            let r = map.local(rider)
            let near = map.near(r, radius: radius)
            func frame(_ w: StreetMap.Way) -> [(Double, Double)] {
                w.pts.map { StreetMap.riderFrame($0, from: r, heading: h) }
            }
            var park = Path(), walk = Path(), walkEdge = Path(), kerb = Path(), road = Path(), bike = Path()
            var paint = Path(), zebra = Path(), caps = Path(), kerbCaps = Path()
            var buildings: [(z: Double, pts: [(Double, Double)])] = []
            for w in near {
                let line = frame(w)
                switch w.kind {
                case .park:
                    if let p = polygon(line) { park.addPath(p) }
                case .path:
                    for run in clip(line) {
                        walkEdge.addPath(RouteRibbon.path(run, width: w.width + 0.5))
                        walk.addPath(RouteRibbon.path(run, width: w.width))
                    }
                case .crossing:
                    for run in clip(line) { zebra.addPath(dashes(run, width: w.width, on: 0.5, off: 0.5)) }
                case .road:
                    for run in clip(line) {
                        kerb.addPath(RouteRibbon.path(run, width: w.width + 0.5))
                        road.addPath(RouteRibbon.path(run, width: w.width))
                        // Round ends fill the notch where two ways meet at an angle; their
                        // own paths, because opposite windings would punch holes.
                        for end in [run.first!, run.last!] {
                            caps.addPath(disc(end, w.width / 2)); kerbCaps.addPath(disc(end, w.width / 2 + 0.25))
                        }
                        markings(run, w, paint: &paint, bike: &bike)
                        for (bit, side) in [(1, -1.0), (2, 1.0)] where w.sidewalks & bit != 0 {
                            let edge = offset(run, by: side * (w.width / 2 + 1.4))
                            walkEdge.addPath(RouteRibbon.path(edge, width: 2.3))
                            walk.addPath(RouteRibbon.path(edge, width: 1.8))
                        }
                    }
                case .building:
                    let z = line.map(\.1).reduce(0, +) / Double(line.count)
                    if z > ahead, z < behind { buildings.append((z, line)) }
                }
            }
            ctx.fill(park, with: .color(Palette.park))
            ctx.fill(walkEdge, with: .color(Palette.sidewalkEdge))
            ctx.fill(walk, with: .color(Palette.sidewalk))
            ctx.fill(kerb, with: .color(Palette.kerb))
            ctx.fill(kerbCaps, with: .color(Palette.kerb))
            ctx.fill(road, with: .color(Palette.street))
            ctx.fill(caps, with: .color(Palette.street))
            ctx.fill(bike, with: .color(Palette.bikeLane))
            ctx.fill(paint, with: .color(Palette.lane))
            ctx.fill(zebra, with: .color(Palette.lane))
            // Far first, so nearer blocks overlap them; the roof is lifted off the
            // footprint, which reads as walls from this camera.
            for b in buildings.sorted(by: { $0.z < $1.z }) {
                guard let base = polygon(b.pts), let roof = polygon(b.pts, h: 4) else { continue }
                ctx.fill(base, with: .color(Palette.blockSide))
                ctx.fill(roof, with: .color(Palette.blockTop))
                ctx.stroke(roof, with: .color(Palette.blockBack), lineWidth: 0.5)
            }
        }
        drawRoute(&ctx, route, rider: rider, heading: h)
    }

    // MARK: - Route

    /// The route the rider chose, Google-Maps style: a blue line with a dark edge, the
    /// mock's widths, so it marks a lane rather than covering the road.
    private static func drawRoute(_ ctx: inout GraphicsContext, _ route: [CLLocationCoordinate2D],
                                  rider: CLLocationCoordinate2D, heading h: Double) {
        guard route.count > 1 else { return }
        let k = cos(rider.latitude * .pi / 180)
        let line = route.map {
            StreetMap.riderFrame(((($0.longitude - rider.longitude) * 111_320 * k), ($0.latitude - rider.latitude) * 111_320),
                                 from: (0, 0), heading: h)
        }
        for run in clip(fromRider(line)) {
            ctx.fill(RouteRibbon.path(run, width: 2.1), with: .color(Palette.routeCase))
            ctx.fill(RouteRibbon.path(run, width: 1.5), with: .color(Palette.routeCore))
        }
    }

    /// The route from where the rider is: everything before the nearest point dropped,
    /// and a lead-in from under the puck that joins the route 8 m on, so a few metres of
    /// GPS error reads as a gentle merge instead of a line ending beside the arrow.
    static func fromRider(_ line: [(Double, Double)]) -> [(Double, Double)] {
        var best = (d: Double.infinity, i: 1, q: (0.0, 0.0))
        for i in 1..<line.count {
            let a = line[i - 1], b = line[i], dx = b.0 - a.0, dz = b.1 - a.1, l2 = dx * dx + dz * dz
            let t = l2 > 0 ? min(max(-(a.0 * dx + a.1 * dz) / l2, 0), 1) : 0
            let q = (a.0 + dx * t, a.1 + dz * t), d = hypot(q.0, q.1)
            if d < best.d { best = (d, i, q) }
        }
        guard best.d < 30 else { return line }          // off route: draw it where it is
        let rest = [best.q] + line[best.i...]
        return [(0, 0)] + (cutFront(rest, by: 8) ?? rest)
    }

    // MARK: - Markings

    /// Lane dividers (dashed), the centre line of a two-way road (solid), and a green
    /// strip on each side that OSM tags with a painted bike lane.
    private static func markings(_ run: [(Double, Double)], _ w: StreetMap.Way,
                                 paint: inout Path, bike: inout Path) {
        let lanes = w.lanes > 0 ? w.lanes : (w.width >= 6 ? 2 : 1)
        // Paint stops short of each end, which is where intersections are.
        guard lanes >= 2, let run = trimmed(run, by: 6) else { return }
        let lw = w.width / Double(lanes)
        for i in 1..<lanes {
            let off = -w.width / 2 + Double(i) * lw
            let centre = !w.oneway && (lanes % 2 == 0 ? i == lanes / 2 : false)
            let line = offset(run, by: off)
            paint.addPath(centre ? RouteRibbon.path(line, width: 0.15)
                                 : dashes(line, width: 0.15, on: 3, off: 6))
        }
        if w.bike {
            for side in [-1.0, 1.0] {
                bike.addPath(RouteRibbon.path(offset(run, by: side * (w.width / 2 - 0.8)), width: 1.5))
            }
        }
    }

    /// The line with `d` metres cut off each end, or nil if nothing is left.
    private static func trimmed(_ line: [(Double, Double)], by d: Double) -> [(Double, Double)]? {
        guard let front = cutFront(line, by: d), let both = cutFront(front.reversed(), by: d),
              both.count > 1 else { return nil }
        return both.reversed()
    }

    /// The line with its first `d` metres removed, or nil if it is shorter than that.
    private static func cutFront(_ l: [(Double, Double)], by d: Double) -> [(Double, Double)]? {
        var left = d
        for i in 1..<l.count {
            let a = l[i - 1], b = l[i], len = hypot(b.0 - a.0, b.1 - a.1)
            if len > left {
                let f = left / len
                return [(a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f)] + l[i...]
            }
            left -= len
        }
        return nil
    }

    /// Dashes laid out in metres along the ground, so they shorten with distance.
    private static func dashes(_ line: [(Double, Double)], width: Double, on: Double, off: Double) -> Path {
        var p = Path()
        var s = 0.0, drawing = true, piece: [(Double, Double)] = [line[0]]
        for i in 1..<line.count {
            var a = line[i - 1]
            let b = line[i]
            var left = hypot(b.0 - a.0, b.1 - a.1)
            while left > 0 {
                let step = min(left, (drawing ? on : off) - s)
                let f = step / left
                a = (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f)
                left -= step; s += step
                if drawing { piece.append(a) }
                if s >= (drawing ? on : off) - 1e-9 {
                    if drawing, piece.count > 1 { p.addPath(RouteRibbon.path(piece, width: width)) }
                    drawing.toggle(); s = 0; piece = [a]
                }
            }
        }
        if drawing, piece.count > 1 { p.addPath(RouteRibbon.path(piece, width: width)) }
        return p
    }

    /// The line shifted `d` metres to its right (negative = left), per-vertex normals.
    private static func offset(_ line: [(Double, Double)], by d: Double) -> [(Double, Double)] {
        line.indices.map { i in
            let a = line[max(i - 1, 0)], b = line[min(i + 1, line.count - 1)]
            let dx = b.0 - a.0, dz = b.1 - a.1, n = max(hypot(dx, dz), 1e-6)
            return (line[i].0 - dz / n * d, line[i].1 + dx / n * d)
        }
    }

    private static func disc(_ c: (Double, Double), _ r: Double) -> Path {
        let p = Camera.pt(c.0, c.1), rr = r * p.s
        return Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2))
    }

    // MARK: - Clipping

    private static func inside(_ p: (Double, Double)) -> Bool {
        p.1 >= ahead && p.1 <= behind && abs(p.0) <= side
    }

    /// The parts of a polyline inside the clip window, each cut exactly at its edge.
    static func clip(_ line: [(Double, Double)]) -> [[(Double, Double)]] {
        var runs: [[(Double, Double)]] = [], cur: [(Double, Double)] = []
        for i in 1..<line.count {
            guard let (a, b) = clipSegment(line[i - 1], line[i]) else {
                if cur.count > 1 { runs.append(cur) }
                cur = []; continue
            }
            if cur.isEmpty { cur = [a] } else if cur.last! != a {
                if cur.count > 1 { runs.append(cur) }
                cur = [a]
            }
            cur.append(b)
            if b != line[i] { runs.append(cur); cur = [] }
        }
        if cur.count > 1 { runs.append(cur) }
        return runs
    }

    /// Liang–Barsky against the z and x limits.
    private static func clipSegment(_ a: (Double, Double), _ b: (Double, Double))
        -> ((Double, Double), (Double, Double))? {
        var t0 = 0.0, t1 = 1.0
        let dx = b.0 - a.0, dz = b.1 - a.1
        for (p, q) in [(-dz, a.1 - ahead), (dz, behind - a.1), (-dx, a.0 + side), (dx, side - a.0)] {
            if p == 0 { if q < 0 { return nil }; continue }
            let r = q / p
            if p < 0 { if r > t1 { return nil }; t0 = max(t0, r) } else { if r < t0 { return nil }; t1 = min(t1, r) }
        }
        return ((a.0 + dx * t0, a.1 + dz * t0), (a.0 + dx * t1, a.1 + dz * t1))
    }

    /// A ground polygon clipped to the window (Sutherland–Hodgman on each edge), h metres up.
    private static func polygon(_ pts: [(Double, Double)], h: Double = 0) -> Path? {
        var poly = pts
        let edges: [((Double, Double)) -> Double] = [
            { $0.1 - ahead }, { behind - $0.1 }, { $0.0 + side }, { side - $0.0 },
        ]
        for f in edges {
            guard !poly.isEmpty else { return nil }
            var out: [(Double, Double)] = []
            for i in poly.indices {
                let a = poly[i], b = poly[(i + 1) % poly.count]
                let fa = f(a), fb = f(b)
                if fa >= 0 { out.append(a) }
                if (fa >= 0) != (fb >= 0) {
                    let t = fa / (fa - fb)
                    out.append((a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t))
                }
            }
            poly = out
        }
        guard poly.count > 2 else { return nil }
        return SceneRenderer.poly(poly.map { Camera.pt($0.0, $0.1, h) })
    }
}
