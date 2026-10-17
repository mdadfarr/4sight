import CoreLocation
import Foundation

/// One near-miss as written by EventLogger. `level` is whichever side was worse.
struct RiskEvent: Identifiable {
    let id: Int
    let timestamp: Date
    let coordinate: CLLocationCoordinate2D?
    let speed: Double
    let leftLevel: Int
    let rightLevel: Int
    let ttcSeconds: Double?
    let gapM: Double
    let cls: String

    var level: Int { max(leftLevel, rightLevel) }
    var side: String { leftLevel > rightLevel ? "left" : rightLevel > leftLevel ? "right" : "both" }
}

/// A 250 m square with the events that fell inside it.
struct GridCell: Identifiable {
    let id: String
    let corners: [CLLocationCoordinate2D]
    let count: Int
    let worstLevel: Int
}

struct RideTrack: Identifiable {
    let id: String
    let points: [CLLocationCoordinate2D]
}

/// Reads Documents/events.jsonl and any ride-*.jsonl, and buckets events into a grid.
/// Parsing and aggregation live here so the view only arranges what it is given.
@MainActor
final class EventStore: ObservableObject {
    @Published private(set) var events: [RiskEvent] = []
    @Published private(set) var cells: [GridCell] = []
    @Published private(set) var tracks: [RideTrack] = []

    static let cellMetres = 250.0
    static let metresPerDegreeLat = 111_320.0

    static var eventsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("events.jsonl")
    }

    var hasFile: Bool { FileManager.default.fileExists(atPath: Self.eventsURL.path) }

    var levelThreeCount: Int { events.filter { $0.level >= 3 }.count }

    /// Total length of every ride track, in kilometres; nil when no ride was logged.
    var riddenKm: Double? {
        let total = tracks.reduce(0.0) { sum, t in
            sum + zip(t.points, t.points.dropFirst()).reduce(0.0) { d, pair in
                d + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                    .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
            }
        }
        return total > 1 ? total / 1000 : nil
    }

    var eventsPerKm: Double? { riddenKm.map { Double(events.count) / $0 } }

    // MARK: - Loading

    func load(demo: Bool) {
        if demo {
            events = Self.demoEvents()
            tracks = [RideTrack(id: "demo", points: Self.demoRoute())]
        } else {
            events = Self.readEvents(at: Self.eventsURL)
            tracks = Self.readRides()
        }
        cells = Self.grid(events)
    }

    private struct Row: Decodable {
        let timestamp: String
        let lat: Double?
        let lon: Double?
        let speed: Double?
        let leftLevel: Int?
        let rightLevel: Int?
        let ttcSeconds: Double?
        let gapM: Double?
        let cls: String?
        let trackId: Int?
    }

    static func readEvents(at url: URL) -> [RiskEvent] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let iso = ISO8601DateFormatter()
        return text.split(separator: "\n").enumerated().compactMap { i, line in
            guard let row = try? decoder.decode(Row.self, from: Data(line.utf8)) else { return nil }
            let coord = (row.lat).flatMap { la in row.lon.map { CLLocationCoordinate2D(latitude: la, longitude: $0) } }
            return RiskEvent(id: i, timestamp: iso.date(from: row.timestamp) ?? .distantPast,
                             coordinate: coord, speed: row.speed ?? 0,
                             leftLevel: row.leftLevel ?? 0, rightLevel: row.rightLevel ?? 0,
                             ttcSeconds: row.ttcSeconds, gapM: row.gapM ?? 0,
                             cls: row.cls ?? "unknown")
        }
    }

    private struct Fix: Decodable { let lat: Double?; let lon: Double? }

    static func readRides() -> [RideTrack] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("ride-") && $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let pts = text.split(separator: "\n").compactMap { line -> CLLocationCoordinate2D? in
                    guard let f = try? JSONDecoder().decode(Fix.self, from: Data(line.utf8)),
                          let la = f.lat, let lo = f.lon else { return nil }
                    return CLLocationCoordinate2D(latitude: la, longitude: lo)
                }
                return pts.count > 1 ? RideTrack(id: url.lastPathComponent, points: pts) : nil
            }
    }

    // MARK: - Grid

    /// Buckets located events into square cells sized at one reference latitude, which
    /// holds across a city. shortcut: cells skew if events ever span more than a degree
    /// of latitude; switch to per-cell longitude scaling if that happens.
    static func grid(_ events: [RiskEvent]) -> [GridCell] {
        let located = events.compactMap { e in e.coordinate.map { (e, $0) } }
        guard !located.isEmpty else { return [] }

        let refLat = located.map(\.1.latitude).reduce(0, +) / Double(located.count)
        let latStep = cellMetres / metresPerDegreeLat
        let lonStep = cellMetres / (metresPerDegreeLat * cos(refLat * .pi / 180))

        var buckets: [String: (row: Int, col: Int, count: Int, worst: Int)] = [:]
        for (event, c) in located {
            let row = Int(floor(c.latitude / latStep)), col = Int(floor(c.longitude / lonStep))
            let key = "\(row):\(col)"
            let prev = buckets[key] ?? (row, col, 0, 0)
            buckets[key] = (row, col, prev.count + 1, max(prev.worst, event.level))
        }

        return buckets.map { key, b in
            let south = Double(b.row) * latStep, west = Double(b.col) * lonStep
            return GridCell(id: key, corners: [
                CLLocationCoordinate2D(latitude: south, longitude: west),
                CLLocationCoordinate2D(latitude: south + latStep, longitude: west),
                CLLocationCoordinate2D(latitude: south + latStep, longitude: west + lonStep),
                CLLocationCoordinate2D(latitude: south, longitude: west + lonStep),
            ], count: b.count, worstLevel: b.worst)
        }
    }

    // MARK: - Demo data

    /// `--demoevents`: a scripted set along Bloor St W and College St so the screen and
    /// the pitch never depend on having ridden with a logging phone.
    static func demoEvents() -> [RiskEvent] {
        let classes = ["car", "car", "car", "truck", "bus", "motorcycle"]
        var out: [RiskEvent] = []
        var id = 0

        func add(_ lat: Double, _ lon: Double, _ level: Int, _ left: Bool, _ gap: Double, _ i: Int) {
            out.append(RiskEvent(id: id, timestamp: Date(timeIntervalSinceNow: Double(-id) * 42),
                                 coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                 speed: 4.4 + Double(i % 5) * 0.4,
                                 leftLevel: left ? level : 0, rightLevel: left ? 0 : level,
                                 ttcSeconds: level >= 3 ? 1.4 : 2.9, gapM: gap,
                                 cls: classes[i % classes.count]))
            id += 1
        }

        // Bloor St W, Keele to Bathurst: the stretch with no separated lane.
        for i in 0..<26 {
            let t = Double(i) / 25
            let jitter = sin(Double(i) * 2.3) * 0.00022
            add(43.6565 + t * 0.0083 + jitter, -79.4650 + t * 0.0540,
                [5, 11, 17, 22].contains(i) ? 3 : 2, i % 3 != 0,
                [5, 11, 17, 22].contains(i) ? 0.7 : 1.2, i)
        }
        // College St, Bathurst eastward.
        for i in 0..<14 {
            let t = Double(i) / 13
            let jitter = cos(Double(i) * 1.9) * 0.00018
            add(43.6555 + t * 0.0025 + jitter, -79.4110 + t * 0.0150,
                i == 4 || i == 9 ? 3 : 2, i % 2 == 0,
                i == 4 || i == 9 ? 0.8 : 1.4, i)
        }
        return out
    }

    /// The matching ridden route, so events per kilometre is a real number in demo mode.
    static func demoRoute() -> [CLLocationCoordinate2D] {
        var pts: [CLLocationCoordinate2D] = []
        for i in 0...60 {
            let t = Double(i) / 60
            pts.append(CLLocationCoordinate2D(latitude: 43.6565 + t * 0.0083, longitude: -79.4650 + t * 0.0540))
        }
        for i in 0...30 {
            let t = Double(i) / 30
            pts.append(CLLocationCoordinate2D(latitude: 43.6648 - t * 0.0093, longitude: -79.4110 + t * 0.0150))
        }
        return pts
    }
}
