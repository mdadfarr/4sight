import Foundation

/// Kerb, a parking lane, then two live lanes. You ride in the door zone.
enum Road {
    static let kerb = 3.7
    static let parked = 2.45
    static let dividers = [-2.3, -5.8]
    static let farEdge = -9.3
}

/// Map data around the rider: streets, blocks and the route. Drawn everywhere,
/// because this is map data rather than anything the rear camera saw.
///
/// Features sit a fixed distance ahead of where the ride starts; riding at `speed`
/// slides them down the screen, so z = speed * t - ahead.
enum World {
    static let speed = 3.6            // m/s, 13 km/h: city cycling
    static let zNear = 60.0
    static let zFar = -280.0

    struct Street {
        let name: String
        let ahead: Double
        let half: Double
        let turn: Bool
    }

    static let streets = [
        Street(name: "Markham St", ahead: 30, half: 5, turn: false),
        Street(name: "Spadina Ave", ahead: 84, half: 7, turn: true),
    ]
    static let turnStreet = streets.first { $0.turn }!

    static func zOf(_ ahead: Double, _ t: Double) -> Double { speed * t - ahead }

    struct Block {
        let x0, x1, a, b, h: Double
        let park: Bool
    }

    /// City blocks either side, cut back at each cross street. Fixed, seeded.
    static let blocks: [Block] = {
        var out: [Block] = []
        var seed = 11
        func rnd() -> Double {
            seed = (seed &* 16807) % 2147483647
            return Double(seed) / 2147483647
        }
        for side in [-1.0, 1.0] {
            let inner = side < 0 ? Road.farEdge - 3.2 : Road.kerb + 3.2
            var w = -80.0
            var parked = false
            while w < 260 {
                let len = 14 + Double(Int(rnd() * 4)) * 4
                if let hit = streets.first(where: { w + len > $0.ahead - $0.half - 3 && w < $0.ahead + $0.half + 3 }) {
                    w = hit.ahead + hit.half + 3
                    continue
                }
                let park = side < 0 && !parked && w > turnStreet.ahead
                if park { parked = true }
                out.append(Block(x0: side < 0 ? inner - 16 : inner,
                                 x1: side < 0 ? inner : inner + 16,
                                 a: w, b: w + len,
                                 h: park ? 0 : 1.2 + rnd() * 1.6, park: park))
                w += len + 3
            }
        }
        return out
    }()

    /// Stretches of main road between cross streets; the pad widens each cut.
    static func spans(_ t: Double, _ pad: Double) -> [(Double, Double)] {
        let cuts = streets.map { st -> (Double, Double) in
            let z = zOf(st.ahead, t)
            return (z - st.half - pad, z + st.half + pad)
        }.sorted { $0.0 < $1.0 }

        var out: [(Double, Double)] = []
        var from = zFar
        for (a, b) in cuts {
            if a > from { out.append((from, min(a, zNear))) }
            from = max(from, b)
        }
        if from < zNear { out.append((from, zNear)) }
        return out.filter { $0.1 > $0.0 }
    }

    static func inStreet(_ z: Double, _ t: Double, _ pad: Double) -> Bool {
        streets.contains { abs(z - zOf($0.ahead, t)) < $0.half + pad }
    }

    /// Centreline of the route: ahead to the turn, a left arc, along the cross street.
    static func routeLine(_ t: Double) -> [(Double, Double)] {
        let zt = zOf(turnStreet.ahead, t)
        let r = 7.0
        var pts: [(Double, Double)] = []
        var z = 0.6
        while z > zt + r {
            pts.append((0, z))
            z -= 2
        }
        for i in 0...14 {
            let a = Double(i) / 14 * .pi / 2
            pts.append((-r + r * cos(a), zt + r - r * sin(a)))
        }
        var x = -r - 3
        while x > -170 {
            pts.append((x, zt))
            x -= 6
        }
        return pts
    }

    /// Footprints in metres, matching VehicleClass in the package.
    static func size(_ cls: String) -> (w: Double, l: Double) {
        switch cls {
        case "truck": return (2.5, 9)
        case "bus": return (2.55, 11)
        case "motorcycle": return (0.8, 2.2)
        case "bicycle": return (0.6, 1.8)
        case "person": return (0.6, 0.6)
        default: return (1.8, 4.5)
        }
    }
}
