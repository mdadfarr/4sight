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
                     heading h: Double, route: [CLLocationCoordinate2D], plan: LanePlan? = nil) {
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
        drawRoute(&ctx, route, plan: plan, rider: rider, heading: h)
    }

    // MARK: - Oncoming lane

    /// Rider-frame x of the middle of the oncoming lane nearest a vehicle at (x, z): the
    /// first lane left of the centre line of the two-way street it is on. Nil off the
    /// map, on a one-way street, or when the measured spot is more than 4 m from that
    /// lane (then the measurement is trusted over the map).
    static func oncomingLane(map: StreetMap?, rider: CLLocationCoordinate2D?, heading h: Double,
                             x: Double, z: Double) -> Double? {
        guard let map, let rider else { return nil }
        let r = map.local(rider), a = h * .pi / 180
        let p = (e: r.e + x * cos(a) - z * sin(a), n: r.n - x * sin(a) - z * cos(a))
        let along = (sin(a), cos(a))                       // the rider's direction, east/north
        var best: (d: Double, centre: (e: Double, n: Double), way: StreetMap.Way)?
        for w in map.near(p, radius: 15) where w.kind == .road && !w.oneway {
            for i in 1..<w.pts.count {
                let s0 = w.pts[i - 1], s1 = w.pts[i], de = s1.e - s0.e, dn = s1.n - s0.n
                let l2 = de * de + dn * dn
                guard l2 > 0.01, abs(de * along.0 + dn * along.1) / l2.squareRoot() > 0.8 else { continue }
                let u = min(max(((p.e - s0.e) * de + (p.n - s0.n) * dn) / l2, 0), 1)
                let q = (e: s0.e + de * u, n: s0.n + dn * u), d = hypot(q.e - p.e, q.n - p.n)
                if d < 15, d < (best?.d ?? .infinity) { best = (d, q, w) }
            }
        }
        guard let best else { return nil }
        let centreX = StreetMap.riderFrame(best.centre, from: r, heading: h).0
        let laneW = best.way.width / 2 / Double(max(best.way.lanes, 2) / 2)
        let lane = centreX - laneW / 2
        return abs(lane - x) < 4 ? lane : nil
    }

    // MARK: - Route

    /// A route point in the rider frame; `c` marks a planned lane change.
    typealias RoutePoint = (x: Double, z: Double, c: Bool)

    /// The route, Google-Maps style: a blue line with a dark edge at the mock's widths,
    /// on the lane the plan picked, smoothed, white with arrows where it moves across.
    private static func drawRoute(_ ctx: inout GraphicsContext, _ route: [CLLocationCoordinate2D], plan: LanePlan?,
                                  rider: CLLocationCoordinate2D, heading h: Double) {
        let k = cos(rider.latitude * .pi / 180)
        func frame(_ lat: Double, _ lon: Double) -> (Double, Double) {
            StreetMap.riderFrame(((lon - rider.longitude) * 111_320 * k, (lat - rider.latitude) * 111_320),
                                 from: (0, 0), heading: h)
        }
        var line: [RoutePoint]
        if let plan, let map = StreetMap.bundled {
            let r = map.local(rider)
            line = plan.samples.map {
                let (x, z) = StreetMap.riderFrame(($0.e, $0.n), from: r, heading: h)
                return (x, z, $0.changing)
            }
        } else {
            line = route.map { let (x, z) = frame($0.latitude, $0.longitude); return (x, z, false) }
        }
        guard line.count > 1 else { return }
        line = smooth(fromRider(line))
        // Split into runs at each change of kind, sharing the boundary point.
        var runs: [(c: Bool, pts: [(Double, Double)])] = []
        for (i, p) in line.enumerated() {
            if i > 0, let last = runs.last, last.c == line[i - 1].c {
                runs[runs.count - 1].pts.append((p.x, p.z))
                if p.c != last.c { runs.append((p.c, [(p.x, p.z)])) }
            } else {
                runs.append((p.c, [(p.x, p.z)]))
            }
        }
        for run in runs where run.pts.count > 1 {
            for piece in clip(run.pts) {
                ctx.fill(RouteRibbon.path(piece, width: 2.1), with: .color(Palette.routeCase))
                ctx.fill(RouteRibbon.path(piece, width: 1.5), with: .color(run.c ? Palette.lane : Palette.routeCore))
                if run.c { ctx.fill(chevrons(piece), with: .color(Palette.routeCore)) }
            }
        }
    }

    /// The route from where the rider is: everything before the nearest point dropped,
    /// and a lead-in from under the puck that joins the route 8 m on, so a few metres of
    /// GPS error reads as a gentle merge instead of a line ending beside the arrow. A
    /// lead-in that crosses more than 1.5 m sideways is itself a move (onto the road,
    /// into the lane) and is drawn as one.
    static func fromRider(_ line: [RoutePoint]) -> [RoutePoint] {
        var best = (d: Double.infinity, i: 1, q: (x: 0.0, z: 0.0))
        for i in 1..<line.count {
            let a = line[i - 1], b = line[i], dx = b.x - a.x, dz = b.z - a.z, l2 = dx * dx + dz * dz
            let t = l2 > 0 ? min(max(-(a.x * dx + a.z * dz) / l2, 0), 1) : 0
            let q = (x: a.x + dx * t, z: a.z + dz * t), d = hypot(q.x, q.z)
            if d < best.d { best = (d, i, q) }
        }
        guard best.d < 30 else { return line }          // off route: draw it where it is
        var rest = [(best.q.x, best.q.z, line[best.i - 1].c)] + line[best.i...]
        var left = 8.0
        while rest.count > 2 {
            let len = hypot(rest[1].x - rest[0].x, rest[1].z - rest[0].z)
            if len > left { break }
            left -= len; rest.removeFirst()
        }
        return [(0, 0, best.d > 1.5)] + rest
    }

    /// Chaikin corner cutting, three rounds: every corner becomes a smooth curve. A new
    /// point keeps the lane-change mark of the segment it was cut from; ends stay put.
    static func smooth(_ line: [RoutePoint]) -> [RoutePoint] {
        var p = line
        for _ in 0..<3 where p.count > 2 {
            var out = [p[0]]
            for i in 0..<(p.count - 1) {
                let a = p[i], b = p[i + 1]
                out.append((a.x * 0.75 + b.x * 0.25, a.z * 0.75 + b.z * 0.25, a.c))
                out.append((a.x * 0.25 + b.x * 0.75, a.z * 0.25 + b.z * 0.75, a.c))
            }
            out.append(p[p.count - 1])
            p = out
        }
        return p
    }

    /// Small arrowheads every 5 m pointing along the line, as Google draws a lane change.
    private static func chevrons(_ line: [(Double, Double)]) -> Path {
        var path = Path(), next = 2.0, s = 0.0
        for i in 1..<line.count {
            let a = line[i - 1], b = line[i], len = hypot(b.0 - a.0, b.1 - a.1)
            guard len > 0 else { continue }
            let ux = (b.0 - a.0) / len, uz = (b.1 - a.1) / len
            while next <= s + len {
                let f = next - s, cx = a.0 + ux * f, cz = a.1 + uz * f
                let tip = Camera.pt(cx + ux * 0.5, cz + uz * 0.5)
                let l = Camera.pt(cx - ux * 0.3 - uz * 0.5, cz - uz * 0.3 + ux * 0.5)
                let r = Camera.pt(cx - ux * 0.3 + uz * 0.5, cz - uz * 0.3 - ux * 0.5)
                path.move(to: tip.cg); path.addLine(to: l.cg); path.addLine(to: r.cg); path.closeSubpath()
                next += 5
            }
            s += len
        }
        return path
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
