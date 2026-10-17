import CoreLocation

/// The real route and the rider's pose, for the heading-up map: like Google Maps, the
/// puck stays fixed pointing up and the map rotates under it.
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

    /// Where the rider is now, carried forward along the GPS course from the last fix
    /// (fixes arrive about once a second), so the map glides instead of hopping.
    /// Capped at 1.5 s: past that the fix is stale and guessing further only drifts.
    func riderCoordinate(at date: Date) -> CLLocationCoordinate2D? {
        guard let rider else { return nil }
        guard rider.speed > 1.5, rider.course >= 0 else { return rider.coordinate }
        let ahead = rider.speed * min(max(date.timeIntervalSince(rider.timestamp), 0), 1.5)
        return Self.offset(rider.coordinate, x: 0, z: -ahead, heading: rider.course)
    }

    /// A point given in the rider's frame — x metres to the right, z metres behind —
    /// as a map coordinate, for a rider at `origin` facing `degrees` from north.
    static func offset(_ origin: CLLocationCoordinate2D, x: Double, z: Double,
                       heading degrees: Double) -> CLLocationCoordinate2D {
        let h = degrees * .pi / 180
        let east = x * cos(h) - z * sin(h)
        let north = -x * sin(h) - z * cos(h)
        let mLat = 111_320.0, mLon = 111_320.0 * cos(origin.latitude * .pi / 180)
        return CLLocationCoordinate2D(latitude: origin.latitude + north / mLat,
                                      longitude: origin.longitude + east / mLon)
    }
}
