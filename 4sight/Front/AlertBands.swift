import SwiftUI

/// The screen-edge warning, drawn last over the nav chrome too: a warning outranks
/// the map. Ported from the mock's `alertZones` / `flashAt` / `edgeBand`.
enum AlertBands {
    enum Zone: String, CaseIterable {
        case left = "L", right = "R", centre = "C"
    }

    static let bandWidth: [Int: Double] = [1: 46, 2: 88, 3: 150]

    /// Worst level in each zone. A track within 0.8 m of centre is straight behind:
    /// there is no side to steer towards, so it lights the whole frame instead.
    static func zones(_ tracks: [VehicleSprite.Track]) -> [Zone: Int] {
        var out: [Zone: Int] = [.left: 0, .right: 0, .centre: 0]
        for tr in tracks where tr.level >= 1 {
            let key: Zone = tr.x < -0.8 ? .left : tr.x > 0.8 ? .right : .centre
            out[key] = max(out[key] ?? 0, tr.level)
        }
        return out
    }

    /// The same beat the grip is playing (CONTRACTS.md): one 300 ms pulse at level 1,
    /// two 350 ms pulses 150 ms apart at level 2, 4 Hz sustained at level 3 (the grip LED).
    /// Eye and hand get the same rhythm, so the screen explains the buzz without being read.
    static func flash(level: Int, age: Double) -> Double {
        if level >= 3 { return (age * 8).truncatingRemainder(dividingBy: 2) < 1 ? 1 : 0.38 }
        if level == 2 {
            if age < 0.35 { return 1 }
            if age < 0.50 { return 0.38 }
            if age < 0.85 { return 1 }
            return 0.62
        }
        return age < 0.30 ? 1 : 0.34
    }

    /// Tracks how long each zone has held its current level, so a flash fires on arrival.
    /// The mock replays its script backwards for this; a live feed has to remember.
    struct History {
        private var entered: [Zone: (level: Int, since: Double)] = [:]

        mutating func update(_ levels: [Zone: Int], now: Double) {
            for zone in Zone.allCases {
                let level = levels[zone] ?? 0
                if entered[zone]?.level != level { entered[zone] = (level, now) }
            }
        }

        func level(_ zone: Zone) -> Int { entered[zone]?.level ?? 0 }

        func age(_ zone: Zone, now: Double) -> Double {
            guard let e = entered[zone] else { return 0 }
            return max(0, now - e.since)
        }
    }

    private static func band(_ ctx: inout GraphicsContext, side: Zone2, colour: Color,
                             width: Double, alpha: Double, canvas: CGSize) {
        let stops = [
            Gradient.Stop(color: colour.opacity(min(1, alpha)), location: 0),
            Gradient.Stop(color: colour.opacity(alpha * 0.88), location: 0.18),
            Gradient.Stop(color: colour.opacity(alpha * 0.4), location: 0.52),
            Gradient.Stop(color: colour.opacity(0), location: 1),
        ]
        let w = canvas.width, h = canvas.height
        let (rect, from, to): (CGRect, CGPoint, CGPoint) = switch side {
        case .l: (CGRect(x: 0, y: 0, width: width, height: h),
                  CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0))
        case .r: (CGRect(x: w - width, y: 0, width: width, height: h),
                  CGPoint(x: w, y: 0), CGPoint(x: w - width, y: 0))
        case .t: (CGRect(x: 0, y: 0, width: w, height: width),
                  CGPoint(x: 0, y: 0), CGPoint(x: 0, y: width))
        case .b: (CGRect(x: 0, y: h - width, width: w, height: width),
                  CGPoint(x: 0, y: h), CGPoint(x: 0, y: h - width))
        }
        ctx.fill(Path(rect), with: .linearGradient(Gradient(stops: stops),
                                                   startPoint: from, endPoint: to))
    }

    private enum Zone2 { case l, r, t, b }

    static func draw(_ ctx: inout GraphicsContext, history: History,
                     now: Double, canvas: CGSize) {
        for zone in Zone.allCases {
            let level = history.level(zone)
            guard level > 0, let width = bandWidth[level] else { continue }
            let colour = level >= 3 ? Palette.red : Palette.amber
            let alpha = flash(level: level, age: history.age(zone, now: now))
            if zone == .centre {
                for side in [Zone2.l, .r, .t, .b] {
                    band(&ctx, side: side, colour: colour, width: width, alpha: alpha, canvas: canvas)
                }
            } else {
                band(&ctx, side: zone == .left ? .l : .r, colour: colour,
                     width: width, alpha: alpha, canvas: canvas)
            }
        }
    }
}
