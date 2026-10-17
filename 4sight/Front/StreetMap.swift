import CoreLocation
import Foundation

/// The real streets, sidewalks, buildings and parks around the rider, from OpenStreetMap
/// (`tools/osm_streets.py` writes `Streets.json`; data © OpenStreetMap contributors).
///
/// Bundled, not fetched on the bike: the public servers are slow and flaky, and a road
/// that appears 30 s late is worse than none. Outside the bundled area the view shows
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

    static let bundled: StreetMap? = {
        guard let url = Bundle.main.url(forResource: "Streets", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? StreetMap(json: data)
    }()

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
    }

    /// A coordinate in this map's metres.
    func local(_ c: CLLocationCoordinate2D) -> (e: Double, n: Double) {
        ((c.longitude - origin.longitude) * 111_320 * cos(origin.latitude * .pi / 180),
         (c.latitude - origin.latitude) * 111_320)
    }

    /// Map metres back to a coordinate; inverse of `local`.
    func coordinate(_ p: (e: Double, n: Double)) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: origin.latitude + p.n / 111_320,
                               longitude: origin.longitude + p.e / (111_320 * cos(origin.latitude * .pi / 180)))
    }

    /// Ways whose bounding box comes within `radius` metres of `p`.
    func near(_ p: (e: Double, n: Double), radius r: Double) -> [Way] {
        ways.filter { $0.lo.e - r < p.e && $0.hi.e + r > p.e && $0.lo.n - r < p.n && $0.hi.n + r > p.n }
    }

    /// Map metres to the rider frame (x right, z behind) for a rider at `r` facing
    /// `heading` degrees from north. Inverse of `LiveRoute.offset`.
    static func riderFrame(_ p: (e: Double, n: Double), from r: (e: Double, n: Double),
                           heading: Double) -> (Double, Double) {
        let h = heading * .pi / 180, de = p.e - r.e, dn = p.n - r.n
        return (cos(h) * de - sin(h) * dn, -sin(h) * de - cos(h) * dn)
    }
}
