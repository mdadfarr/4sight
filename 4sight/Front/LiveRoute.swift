import CoreLocation

/// The real route, turned to face where the rider is going: heading-up, like Google
/// Maps. The puck stays fixed pointing up and the route rotates under it.
///
/// Only the route needs this. The rear camera's tracks are already in the bike's own
/// frame, so they are right-way-up whichever way the rider faces.
struct LiveRoute {
    var coordinates: [CLLocationCoordinate2D] = []
    private(set) var rider: CLLocation?

    /// Heading eases from `from` to `to` over `turn` seconds, so a new fix catches up
    /// rather than snapping. `to` is stored unwrapped (from + shortest delta) so the
    /// ease never spins the long way round through 0°/360°.
    private var from = 0.0, to = 0.0, changedAt = -Double.infinity
    private var hasHeading = false
    static let turn = 0.6

    func heading(at t: Double) -> Double {
        let f = min(max((t - changedAt) / Self.turn, 0), 1)
        return from + (to - from) * f
    }

    mutating func update(_ loc: CLLocation, heading: Double?, at t: Double) {
        rider = loc
        guard let heading else { return }
        if !hasHeading {
            from = heading; to = heading; hasHeading = true
        } else {
            from = self.heading(at: t)
            to = from + Self.shortest(heading - from)
        }
        changedAt = t
    }

    static func shortest(_ d: Double) -> Double {
        var x = d.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }
        if x < -180 { x += 360 }
        return x
    }

    /// One coordinate in the scene's rider frame: x metres to the right, z metres
    /// behind (so the way ahead is negative z, as in `Camera`).
    static func local(_ c: CLLocationCoordinate2D, from origin: CLLocationCoordinate2D,
                      heading degrees: Double) -> (Double, Double) {
        let mLat = 111_320.0, mLon = 111_320.0 * cos(origin.latitude * .pi / 180)
        let east = (c.longitude - origin.longitude) * mLon
        let north = (c.latitude - origin.latitude) * mLat
        let h = degrees * .pi / 180
        return (east * cos(h) - north * sin(h), -(east * sin(h) + north * cos(h)))
    }

    /// The way still to ride, from the rider forward, in the scene's frame. Starts at
    /// the puck so the ribbon leaves from under the arrow, not from the nearest vertex.
    func line(at t: Double) -> [(Double, Double)] {
        guard let rider, hasHeading, coordinates.count > 1 else { return [] }
        let h = heading(at: t)
        let pts = coordinates.map { Self.local($0, from: rider.coordinate, heading: h) }
        let near = pts.indices.min { hypot(pts[$0].0, pts[$0].1) < hypot(pts[$1].0, pts[$1].1) } ?? 0
        var out: [(Double, Double)] = [(0, 0)]
        // Stop past the far plane, or if the route doubles back behind the camera,
        // where the projection is no longer defined.
        for p in pts[(near + 1)...] where out.count < 400 {
            if p.1 < World.zFar || p.1 > 25 { break }
            out.append(p)
        }
        return out.count > 1 ? out : []
    }
}
