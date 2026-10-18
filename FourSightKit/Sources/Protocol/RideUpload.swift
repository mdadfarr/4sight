import Foundation

/// The body of `POST /v1/rides` (docs/DATA_PIPELINE.md). Built once per ride by `RideLog`.
public struct RideUpload: Codable, Equatable, Sendable {
    public struct Event: Codable, Equatable, Sendable {
        /// Epoch seconds.
        public var t: Double
        public var lat: Double
        public var lon: Double
        public var cls: VehicleClass
        /// 2 threat, 3 imminent.
        public var level: Int
        /// "L" | "R" | "-", which grip.
        public var side: String
        public var gapM: Double
        public var ttcS: Double?
        /// The rider's own speed, m/s.
        public var speed: Double

        public init(t: Double, lat: Double, lon: Double, cls: VehicleClass, level: Int,
                    side: String, gapM: Double, ttcS: Double?, speed: Double) {
            self.t = t; self.lat = lat; self.lon = lon; self.cls = cls; self.level = level
            self.side = side; self.gapM = gapM; self.ttcS = ttcS; self.speed = speed
        }

        enum CodingKeys: String, CodingKey {
            case t, lat, lon, cls, level, side, speed
            case gapM = "gap_m"
            case ttcS = "ttc_s"
        }

        /// Synthesised encoding drops a nil key; the contract wants `"ttc_s": null`.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(t, forKey: .t); try c.encode(lat, forKey: .lat); try c.encode(lon, forKey: .lon)
            try c.encode(cls, forKey: .cls); try c.encode(level, forKey: .level); try c.encode(side, forKey: .side)
            try c.encode(gapM, forKey: .gapM); try c.encode(ttcS, forKey: .ttcS); try c.encode(speed, forKey: .speed)
        }
    }

    public var install: String
    public var app: String
    public var demo: Bool
    public var started: Date
    public var ended: Date
    /// [epoch s, lat, lon, speed m/s], at most 1 Hz, already trimmed.
    public var points: [[Double]]
    public var events: [Event]

    /// The request body: ISO 8601 dates, as the server parses them.
    public func json() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }

    /// The server's limits. Rounded as RideLog stores them, 20 000 points stay under its 1 MB.
    static let maxPoints = 20_000, maxEvents = 500

    /// Drops every point within `metres` of the ride's start or end, measured along the
    /// path, so the upload never begins or ends at a door. The public map never shows a
    /// ride's track (only street totals and unlinked near misses), so 50 m is enough.
    public static func trim(_ points: [[Double]], metres: Double = 50) -> [[Double]] {
        guard points.count > 1 else { return [] }
        var along = [0.0]
        for (a, b) in zip(points, points.dropFirst()) { along.append(along.last! + distance(a, b)) }
        let total = along.last!
        return zip(points, along).filter { $0.1 >= metres && total - $0.1 >= metres }.map(\.0)
    }

    /// Haversine metres between two `[t, lat, lon, …]` points.
    static func distance(_ a: [Double], _ b: [Double]) -> Double {
        let r = 6_371_000.0, rad = Double.pi / 180
        let dLat = (b[1] - a[1]) * rad, dLon = (b[2] - a[2]) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a[1] * rad) * cos(b[1] * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}

/// One ride as it happens: GPS points at most 1 Hz and each vehicle's worst moment.
/// Pure, so the trimming and the one-per-vehicle rule are checked without a phone.
public struct RideLog: Sendable {
    public private(set) var points: [[Double]] = []
    /// Every level ≥ 2 sighting; reduced to one per vehicle only after trimming, so a
    /// vehicle seen in a trimmed end and again mid-ride still counts once.
    private var sightings: [(id: Int, event: RideUpload.Event)] = []

    public init() {}

    /// Stored rounded (0.1 s, ~0.1 m, 0.1 m/s): finer than GPS can tell, and half the bytes.
    public mutating func add(t: Double, lat: Double, lon: Double, speed: Double) {
        let t = round(t, 10)
        if let last = points.last, t - last[0] < 1 { return }
        points.append([t, round(lat, 1e6), round(lon, 1e6), round(speed, 10)])
    }

    public mutating func add(track id: Int, _ e: RideUpload.Event) {
        guard e.level >= 2 else { return }
        var e = e
        e.t = round(e.t, 10); e.lat = round(e.lat, 1e6); e.lon = round(e.lon, 1e6)
        e.gapM = round(e.gapM, 100); e.ttcS = e.ttcS.map { round($0, 100) }; e.speed = round(e.speed, 10)
        sightings.append((id, e))
    }

    private func round(_ v: Double, _ scale: Double) -> Double { (v * scale).rounded() / scale }

    /// The ride as uploads, trimmed; empty when nothing is left to send. Events inside the
    /// trimmed ends go too, since their position would give the same places away. A ride over
    /// 20 000 points (5.5 h) goes as several consecutive uploads rather than losing any of it.
    /// started/ended are the kept points' times, so they do not reveal the trimmed ends either.
    public func uploads(install: String, app: String, demo: Bool) -> [RideUpload] {
        let kept = RideUpload.trim(points)
        return stride(from: 0, to: kept.count, by: RideUpload.maxPoints).map { start in
            let chunk = Array(kept[start..<min(start + RideUpload.maxPoints, kept.count)])
            let from = chunk[0][0], to = start + chunk.count < kept.count ? kept[start + chunk.count][0] : chunk.last![0] + 0.01
            // One event per track id: the first moment it reached its worst level.
            var worst: [Int: RideUpload.Event] = [:]
            for (id, e) in sightings where e.t >= from && e.t < to && (worst[id]?.level ?? 0) < e.level {
                worst[id] = e
            }
            // shortcut: over 500 near misses in 5.5 h keeps the first 500; split by events too if that ever happens.
            let events = worst.values.sorted { $0.t < $1.t }.prefix(RideUpload.maxEvents)
            return RideUpload(install: install, app: app, demo: demo,
                              started: Date(timeIntervalSince1970: from), ended: Date(timeIntervalSince1970: chunk.last![0]),
                              points: chunk, events: Array(events))
        }
    }
}
