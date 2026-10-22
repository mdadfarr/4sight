import CoreLocation
import Foundation

/// The real streets, sidewalks, buildings and parks around the rider, from OpenStreetMap
/// (`tools/osm_streets.py` writes one `Streets-<region>.deflate` per city and lists its box in
/// `StreetRegions.json`; data © OpenStreetMap contributors).
///
/// Bundled, not fetched on the bike: the public servers are slow and flaky, and a road
/// that appears 30 s late is worse than none. Outside every bundled region the view shows
/// only the route.
struct StreetMap {
    enum Kind: String, Decodable { case park, path, crossing, road, building }

    struct Way {
        let kind: Kind
        let width: Double
        let lanes: Int
        let oneway: Bool
        let bike: Bool
        /// Sidewalks tagged on the road itself: bit 1 left, bit 2 right of its direction.
        let sidewalks: Int
        /// Metres east and north of `origin`.
        let pts: [(e: Double, n: Double)]
        let lo: (e: Double, n: Double), hi: (e: Double, n: Double)
    }

    let origin: CLLocationCoordinate2D
    let ways: [Way]
    /// Way indices by 250 m square, so `near` reads a few squares, not a whole city.
    private let grid: [Cell: [Int]]
    private struct Cell: Hashable { let i: Int, j: Int }
    private static let cellSize = 250.0

    /// The region holding `c`, once loaded; nil outside every region, and for the second
    /// or so a city takes to load in the background, so drawing never waits on it.
    static func at(_ c: CLLocationCoordinate2D?) -> StreetMap? { Regions.shared.map(at: c, wait: false) }

    /// The same, waiting for the load. Off the main thread, or for the small preview region.
    static func loaded(at c: CLLocationCoordinate2D?) -> StreetMap? { Regions.shared.map(at: c, wait: true) }

    private struct Raw: Decodable {
        struct W: Decodable { let k: Kind; let p: [Int]; let w: Double?; let n: Int?; let one: Int?; let bike: Int?; let sw: Int? }
        let origin: [Double]
        let ways: [W]
    }

    init(json: Data) throws {
        let raw = try JSONDecoder().decode(Raw.self, from: json)
        origin = CLLocationCoordinate2D(latitude: raw.origin[0], longitude: raw.origin[1])
        ways = raw.ways.compactMap { w in
            let pts = stride(from: 0, to: w.p.count - 1, by: 2).map {
                (e: Double(w.p[$0]) / 10, n: Double(w.p[$0 + 1]) / 10)
            }
            guard pts.count > 1 else { return nil }
            return Way(kind: w.k, width: w.w ?? 0, lanes: w.n ?? 0, oneway: w.one == 1, bike: w.bike == 1, sidewalks: w.sw ?? 0,
                       pts: pts,
                       lo: (pts.map(\.e).min()!, pts.map(\.n).min()!),
                       hi: (pts.map(\.e).max()!, pts.map(\.n).max()!))
        }
        var grid: [Cell: [Int]] = [:]
        for (k, w) in ways.enumerated() {
            for i in Self.cell(w.lo.e)...Self.cell(w.hi.e) {
                for j in Self.cell(w.lo.n)...Self.cell(w.hi.n) { grid[Cell(i: i, j: j), default: []].append(k) }
            }
        }
        self.grid = grid
        #if DEBUG
        // The index must find exactly what a scan of every way finds.
        for p in [(e: 0.0, n: 0.0)] + ways.prefix(3).map({ $0.pts[0] }) {
            let scan = ways.filter { $0.lo.e - 320 < p.e && $0.hi.e + 320 > p.e && $0.lo.n - 320 < p.n && $0.hi.n + 320 > p.n }
            assert(near(p, radius: 320).count == scan.count, "street grid disagrees with a full scan")
        }
        #endif
    }

    private static func cell(_ metres: Double) -> Int { Int((metres / cellSize).rounded(.down)) }

    /// A coordinate in this map's metres.
    func local(_ c: CLLocationCoordinate2D) -> (e: Double, n: Double) {
        ((c.longitude - origin.longitude) * 111_320 * cos(origin.latitude * .pi / 180),
         (c.latitude - origin.latitude) * 111_320)
    }

    /// Where the rider stands relative to the street network: metres to the nearest road or
    /// path, and whether they are inside a mapped building. Nil when no street is mapped
    /// within 200 m (outside the bundled area), where the map cannot tell.
    func networkGap(_ c: CLLocationCoordinate2D) -> (metres: Double, indoors: Bool)? {
        let p = local(c)
        let around = near(p, radius: 200)
        let ways = around.filter { $0.kind == .road || $0.kind == .path || $0.kind == .crossing }
        guard !ways.isEmpty else { return nil }
        var best = Double.infinity
        for w in ways {
            for i in 1..<w.pts.count {
                let a = w.pts[i - 1], b = w.pts[i], de = b.e - a.e, dn = b.n - a.n, l2 = de * de + dn * dn
                let t = l2 > 0 ? min(max(((p.e - a.e) * de + (p.n - a.n) * dn) / l2, 0), 1) : 0
                best = min(best, hypot(a.e + de * t - p.e, a.n + dn * t - p.n) - (w.width / 2))
            }
        }
        let indoors = around.contains { $0.kind == .building && Self.inside(p, $0.pts) }
        return (max(best, 0), indoors)
    }

    /// Even-odd point-in-polygon on map metres.
    static func inside(_ p: (e: Double, n: Double), _ ring: [(e: Double, n: Double)]) -> Bool {
        var hit = false, j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.n > p.n) != (b.n > p.n), p.e < (b.e - a.e) * (p.n - a.n) / (b.n - a.n) + a.e { hit.toggle() }
            j = i
        }
        return hit
    }

    /// Map metres back to a coordinate; inverse of `local`.
    func coordinate(_ p: (e: Double, n: Double)) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: origin.latitude + p.n / 111_320,
                               longitude: origin.longitude + p.e / (111_320 * cos(origin.latitude * .pi / 180)))
    }

    /// Ways whose bounding box comes within `radius` metres of `p`, in file (draw) order.
    func near(_ p: (e: Double, n: Double), radius r: Double) -> [Way] {
        var found = Set<Int>()
        for i in Self.cell(p.e - r)...Self.cell(p.e + r) {
            for j in Self.cell(p.n - r)...Self.cell(p.n + r) { found.formUnion(grid[Cell(i: i, j: j)] ?? []) }
        }
        return found.sorted().map { ways[$0] }
            .filter { $0.lo.e - r < p.e && $0.hi.e + r > p.e && $0.lo.n - r < p.n && $0.hi.n + r > p.n }
    }

    /// Map metres to the rider frame (x right, z behind) for a rider at `r` facing
    /// `heading` degrees from north. Inverse of `LiveRoute.offset`.
    static func riderFrame(_ p: (e: Double, n: Double), from r: (e: Double, n: Double),
                           heading: Double) -> (Double, Double) {
        let h = heading * .pi / 180, de = p.e - r.e, dn = p.n - r.n
        return (cos(h) * de - sin(h) * dn, -sin(h) * de - cos(h) * dn)
    }
}

/// The bundled cities. One is kept in memory at a time: the one the rider is in.
private final class Regions: @unchecked Sendable {
    static let shared = Regions()
    private struct Region: Decodable { let name: String; let s, w, n, e: Double }
    private let regions: [Region]
    private let lock = NSLock()
    /// The region in use; its map is nil while it loads (or if its file is missing).
    private var current: (name: String, map: StreetMap?)?

    private init() {
        regions = Bundle.main.url(forResource: "StreetRegions", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([Region].self, from: $0) } ?? []
    }

    func map(at c: CLLocationCoordinate2D?, wait: Bool) -> StreetMap? {
        guard let c, let r = regions.first(where: {
            c.latitude >= $0.s && c.latitude <= $0.n && c.longitude >= $0.w && c.longitude <= $0.e
        }) else { return nil }
        lock.lock()
        if let cur = current, cur.name == r.name, cur.map != nil || !wait {
            lock.unlock()
            return cur.map
        }
        current = (r.name, nil)
        lock.unlock()
        guard wait else {
            DispatchQueue.global(qos: .userInitiated).async { _ = self.load(r.name) }
            return nil
        }
        return load(r.name)
    }

    private func load(_ name: String) -> StreetMap? {
        // Raw DEFLATE: a city's JSON is a third the size, and inflating it costs ~0.1 s.
        let map = Bundle.main.url(forResource: "Streets-\(name)", withExtension: "deflate")
            .flatMap { try? NSData(contentsOf: $0).decompressed(using: .zlib) as Data }
            .flatMap { try? StreetMap(json: $0) }
        lock.lock()
        if current?.name == name { current = (name, map) }
        lock.unlock()
        return map
    }
}
