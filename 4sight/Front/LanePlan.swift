import CoreLocation
import Foundation

/// Where on the street to ride along the route, like Google Maps lane guidance: the
/// bike lane where OSM has one, else the right-hand lane; the left lane of your own
/// direction before a left turn on a multi-lane road; the sidewalk along a big road
/// with no bike lane, where one is mapped. Planned from the map and the route, not
/// measured: phone GPS (3–5 m) cannot tell lanes apart.
///
/// The route line is moved onto that spot, and each move is a `changing` stretch the
/// renderer draws white with arrows and the banner announces.
struct LanePlan {
    enum Spot: Equatable { case road, bikeLane, rightLane, leftLane, sidewalk }

    struct Sample {
        let e, n: Double       // map metres, already moved onto the spot
        let s: Double          // metres along the route
        let spot: Spot
        let changing: Bool
    }

    let samples: [Sample]
    let map: StreetMap

    static let step = 4.0
    /// Hold the left lane this far before a left turn.
    static let leftTurnLead = 70.0
    /// Sideways speed of a planned move: 1 m across per this many metres along.
    static let ramp = 4.0

    init?(route: [CLLocationCoordinate2D], map: StreetMap) {
        guard route.count > 1 else { return nil }
        self.map = map
        let pts = Self.resample(route.map { map.local($0) }, every: Self.step)
        guard pts.count > 3 else { return nil }
        // Direction over ±12 m, so the sideways push turns gradually through a corner.
        let dirs = pts.indices.map { i -> (Double, Double) in
            let a = pts[max(i - 3, 0)], b = pts[min(i + 3, pts.count - 1)]
            let l = max(hypot(b.e - a.e, b.n - a.n), 1e-6)
            return ((b.e - a.e) / l, (b.n - a.n) / l)
        }
        let turns = Self.leftTurns(dirs)
        let lo = (pts.map(\.e).min()!, pts.map(\.n).min()!), hi = (pts.map(\.e).max()!, pts.map(\.n).max()!)
        let ways = map.ways.filter {
            ($0.kind == .road || $0.kind == .path)
                && $0.hi.e > lo.0 - 30 && $0.lo.e < hi.0 + 30 && $0.hi.n > lo.1 - 30 && $0.lo.n < hi.1 + 30
        }
        let roads = ways.filter { $0.kind == .road }, paths = ways.filter { $0.kind == .path }

        // Target spot and lateral offset (metres right of the road centre, along travel).
        var target: [(spot: Spot, lat: Double, centre: (e: Double, n: Double)?)] = []
        for (i, p) in pts.enumerated() {
            let d = dirs[i], s = Double(i) * Self.step
            guard let m = Self.nearest(p, d, in: roads, within: 7) else {
                target.append((.road, target.last?.lat ?? 0, nil)); continue
            }
            let w = m.way, h = w.width / 2
            let twoWay = !w.oneway
            let lanesHere = max(twoWay ? max(w.lanes, 2) / 2 : max(w.lanes, 1), 1)
            let laneW = (twoWay ? h : w.width) / Double(lanesHere)
            let leftTurnSoon = turns.contains { $0 > s && $0 - s < Self.leftTurnLead }
            let big = (twoWay && w.lanes >= 4) || (!twoWay && w.lanes >= 3) || w.width >= 12
            let walk = big && !w.bike ? Self.sidewalk(m.centre, d, in: paths, beyond: h) : nil
            if leftTurnSoon && lanesHere >= 2 {
                target.append((.leftLane, (twoWay ? 0 : -h) + laneW / 2, m.centre))
            } else if w.bike {
                target.append((.bikeLane, h - 0.8, m.centre))
            } else if let walk {
                target.append((.sidewalk, walk, m.centre))
            } else {
                target.append((.rightLane, h - min(laneW, 3.3) / 2, m.centre))
            }
        }
        // A spot held for under 20 m is a matching glitch (an intersection, a slip
        // lane), not a plan: keep the previous one through it.
        let minRun = Int(20 / Self.step)
        var k = 0
        while k < target.count {
            var j = k
            while j + 1 < target.count && target[j + 1].spot == target[k].spot { j += 1 }
            if j - k + 1 < minRun, k > 0 {
                for x in k...j { target[x] = (target[k - 1].spot, target[k - 1].lat, target[x].centre) }
            }
            k = j + 1
        }
        // Move sideways at a limited rate, so a change is a visible diagonal stretch.
        var out: [Sample] = [], lat = target[0].lat
        for (i, p) in pts.enumerated() {
            let goal = target[i].lat, maxStep = Self.step / Self.ramp
            let next = lat + min(max(goal - lat, -maxStep), maxStep)
            let changing = abs(next - lat) > 0.05
            lat = next
            let base = target[i].centre ?? p
            let right = (dirs[i].1, -dirs[i].0)                  // east/north: right of travel
            let q = Sample(e: base.e + right.0 * lat, n: base.n + right.1 * lat,
                           s: Double(i) * Self.step, spot: target[i].spot, changing: changing)
            // Pushed out on the inside of a tight corner, the line would loop back on
            // itself: drop any point that does not move forward along the route.
            if let last = out.last, (q.e - last.e) * dirs[i].0 + (q.n - last.n) * dirs[i].1 < 0.5 { continue }
            out.append(q)
        }
        samples = out
    }

    // MARK: - Banner

    /// What the banner says about the next planned move within `horizon` metres of
    /// `rider`, or nil while the plan is steady. Also nil off the route.
    func cue(at rider: CLLocationCoordinate2D, horizon: Double = 150) -> (text: String, symbol: String, metres: Double)? {
        let r = map.local(rider)
        guard let i = samples.indices.min(by: {
            hypot(samples[$0].e - r.e, samples[$0].n - r.n) < hypot(samples[$1].e - r.e, samples[$1].n - r.n)
        }), hypot(samples[i].e - r.e, samples[i].n - r.n) < 30 else { return nil }
        let here = samples[i]
        guard let next = samples[i...].first(where: { $0.spot != here.spot && $0.s - here.s <= horizon }) else { return nil }
        let toLeft = next.spot == .leftLane || here.spot == .sidewalk
        let text: String
        switch next.spot {
        case .bikeLane: text = "Move into the bike lane"
        case .leftLane: text = "Move to the left lane to turn left"
        case .rightLane: text = here.spot == .sidewalk ? "Back onto the road" : "Keep to the right lane"
        case .sidewalk: text = "Use the sidewalk"
        case .road: return nil
        }
        return (text, toLeft ? "arrow.up.left" : "arrow.up.right", next.s - here.s)
    }

    // MARK: - Geometry

    private static func resample(_ line: [(e: Double, n: Double)], every d: Double) -> [(e: Double, n: Double)] {
        var out = [line[0]], carry = 0.0
        for i in 1..<line.count {
            let a = line[i - 1], b = line[i], len = hypot(b.e - a.e, b.n - a.n)
            var t = d - carry
            while t <= len {
                out.append((a.e + (b.e - a.e) * t / len, a.n + (b.n - a.n) * t / len)); t += d
            }
            carry = len - (t - d)
        }
        return out
    }

    /// Route distances of left turns: heading swings more than 50° to the left between
    /// 16 m before and 16 m after, at the sharpest point of each swing.
    private static func leftTurns(_ dirs: [(Double, Double)]) -> [Double] {
        let k = Int(16 / step)
        var turns: [Double] = [], best = (cross: 0.0, i: -1)
        for i in dirs.indices.dropFirst(k).dropLast(k) {
            let a = dirs[i - k], b = dirs[i + k]
            let cross = a.0 * b.1 - a.1 * b.0              // > 0: counter-clockwise, a left
            let dot = a.0 * b.0 + a.1 * b.1
            if cross > 0 && dot < cos(50 * .pi / 180) {
                if cross > best.cross { best = (cross, i) }
            } else if best.i >= 0 {
                turns.append(Double(best.i) * step); best = (0, -1)
            }
        }
        return turns
    }

    /// The nearest way segment within `r` metres running roughly along `d`, and the
    /// point on it nearest `p`.
    private static func nearest(_ p: (e: Double, n: Double), _ d: (Double, Double), in ways: [StreetMap.Way],
                                within r: Double) -> (way: StreetMap.Way, centre: (e: Double, n: Double))? {
        var best: (StreetMap.Way, (e: Double, n: Double), Double)?
        for w in ways where w.lo.e - r < p.e && w.hi.e + r > p.e && w.lo.n - r < p.n && w.hi.n + r > p.n {
            for i in 1..<w.pts.count {
                let a = w.pts[i - 1], b = w.pts[i], de = b.e - a.e, dn = b.n - a.n
                let l2 = de * de + dn * dn
                guard l2 > 0.01 else { continue }
                let l = l2.squareRoot()
                guard abs((de * d.0 + dn * d.1) / l) > 0.85 else { continue }   // parallel either way
                let t = min(max(((p.e - a.e) * de + (p.n - a.n) * dn) / l2, 0), 1)
                let q = (e: a.e + de * t, n: a.n + dn * t), dist = hypot(q.e - p.e, q.n - p.n)
                if dist < r, dist < (best?.2 ?? .infinity) { best = (w, q, dist) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Lateral offset (right of `c` along `d`) of a parallel sidewalk on the right
    /// between the kerb and 12 m beyond it, or nil.
    private static func sidewalk(_ c: (e: Double, n: Double), _ d: (Double, Double),
                                 in paths: [StreetMap.Way], beyond h: Double) -> Double? {
        let right = (d.1, -d.0)
        let probe = (e: c.e + right.0 * (h + 4), n: c.n + right.1 * (h + 4))
        guard let m = nearest(probe, d, in: paths, within: 8) else { return nil }
        let lat = (m.centre.e - c.e) * right.0 + (m.centre.n - c.n) * right.1
        return lat > h && lat < h + 12 ? lat : nil
    }
}
