import SwiftUI

/// Detected traffic, ported from the mock's `drawVehicle` / `drawPerson` / `drawCyclist`.
///
/// Vehicles are an extruded body box with a greenhouse on top and carry the alert in
/// their own fill. People and cyclists are drawn as upright figures instead: from
/// near-overhead a real person is shoulders and a head, which reads as nothing in
/// particular, so standing them up is what makes "person" register at a glance.
enum VehicleSprite {

    struct Track {
        let id: Int
        let cls: String
        let x, z: Double
        let level: Int
        let turnR: Bool
        /// Display only: fades a track in when it appears and out when it goes.
        var opacity = 1.0
        /// Travelling the other way: drawn with its windscreen away from the rider.
        var oncoming = false
    }

    static func draw(_ ctx: inout GraphicsContext, _ tr: Track, _ t: Double) {
        switch tr.cls {
        case "person": person(&ctx, tr, t)
        case "bicycle": cyclist(&ctx, tr, t)
        default: vehicle(&ctx, tr, t)
        }
    }

    // MARK: - Vehicles

    private static func vehicle(_ ctx: inout GraphicsContext, _ tr: Track, _ t: Double) {
        let (w, l) = World.size(tr.cls)
        let big = tr.cls == "bus" || tr.cls == "truck"
        let hBody = big ? 2.4 : 0.95, hRoof = big ? 3.0 : 1.45
        let col = Palette.paint(tr.level)
        let s = Camera.ppm(tr.z)
        let r = max(2, 0.34 * s)
        let d = tr.oncoming ? -1.0 : 1.0                 // which end is the front

        if tr.level >= 3 {                                   // glow, breathing at 1 Hz
            var layer = ctx
            layer.opacity = 0.3 + 0.35 * abs(sin(.pi * t))
            layer.addFilter(.shadow(color: Palette.red, radius: 12))
            layer.fill(SceneRenderer.roundQuad(Camera.slab(tr.x, tr.z, w, l, 0.05), r),
                       with: .color(Palette.red))
        }

        ctx.fill(SceneRenderer.poly(Camera.slab(tr.x + 0.12, tr.z + 0.12, w, l)),
                 with: .color(Palette.shadow))

        let body = SceneRenderer.roundQuad(Camera.slab(tr.x, tr.z, w, l, hBody), r)
        ctx.fill(body, with: .color(col.body))
        ctx.stroke(body, with: .color(col.edge), lineWidth: 1.2)

        ctx.fill(SceneRenderer.roundQuad(
            Camera.slab(tr.x, tr.z + d * l * 0.06, w * 0.74, l * (big ? 0.74 : 0.44), hRoof), r * 0.6),
                 with: .color(col.roof))

        ctx.fill(SceneRenderer.poly(
            Camera.slab(tr.x, tr.z - d * l * (big ? 0.3 : 0.12), w * 0.68, l * 0.09, hRoof)),
                 with: .color(col.glass))

        if tr.turnR && sin(.pi * 1.6 * t) > 0 {              // right indicator, blinking
            ctx.fill(SceneRenderer.poly(
                Camera.slab(tr.x + w / 2 - 0.2, tr.z - l / 2 + 0.25, 0.32, 0.32, hBody)),
                     with: .color(Palette.amber))
        }
    }

    // MARK: - People and cyclists

    /// Geometry in metres, y measured up from the feet.
    private enum Part {
        case box(Color, x: Double, y0: Double, w: Double, y1: Double, r: Double)
        case line(Color, x0: Double, y0: Double, x1: Double, y1: Double, width: Double)
        case head(Color, x: Double, y: Double, rx: Double, ry: Double)
    }

    private static func path(_ part: Part, _ foot: Projected, _ u: Double) -> Path {
        func at(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: foot.x + x * u, y: foot.y - y * u)
        }
        switch part {
        case let .box(_, x, y0, w, y1, r):
            let origin = at(x - w / 2, y1)
            let rect = CGRect(x: origin.x, y: origin.y, width: w * u, height: (y1 - y0) * u)
            return Path(roundedRect: rect, cornerRadius: min(r * u, w * u / 2))
        case let .line(_, x0, y0, x1, y1, _):
            var p = Path()
            p.move(to: at(x0, y0))
            p.addLine(to: at(x1, y1))
            return p
        case let .head(_, x, y, rx, ry):
            let c = at(x, y)
            return Path(ellipseIn: CGRect(x: c.x - rx * u, y: c.y - ry * u,
                                          width: rx * 2 * u, height: ry * 2 * u))
        }
    }

    /// Paint a figure twice: a white halo pass with a wide stroke, then the colours.
    private static func figure(_ ctx: inout GraphicsContext, _ foot: Projected,
                               _ u: Double, _ parts: [Part]) {
        let style = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
        for part in parts {
            let w: Double = if case let .line(_, _, _, _, _, lw) = part { lw * u + 3.5 } else { 3.5 }
            ctx.stroke(path(part, foot, u), with: .color(Palette.VRU.halo),
                       style: style.with(lineWidth: w))
        }
        for part in parts {
            let p = path(part, foot, u)
            switch part {
            case let .line(colour, _, _, _, _, lw):
                ctx.stroke(p, with: .color(colour), style: style.with(lineWidth: lw * u))
            case let .box(colour, _, _, _, _, _), let .head(colour, _, _, _, _):
                ctx.fill(p, with: .color(colour))
            }
        }
    }

    private static func groundShadow(_ ctx: inout GraphicsContext, _ foot: Projected,
                                     _ u: Double, _ rx: Double) {
        let rect = CGRect(x: foot.x - rx * u, y: foot.y - rx * u * 0.38,
                          width: rx * 2 * u, height: rx * 2 * u * 0.38)
        ctx.fill(Path(ellipseIn: rect), with: .color(Palette.shadow))
    }

    /// Another rider, seen from behind: rear wheel, legs, back, arms to the bars, helmet.
    private static func cyclist(_ ctx: inout GraphicsContext, _ tr: Track, _ t: Double) {
        let foot = Camera.pt(tr.x, tr.z)
        let u = foot.s * Palette.VRU.scale
        let col = Palette.vruColour(tr.level)
        groundShadow(&ctx, foot, u, 0.36)
        figure(&ctx, foot, u, [
            .box(col.limb, x: 0, y0: 0.0, w: 0.08, y1: 0.68, r: 0.04),
            .line(col.limb, x0: -0.11, y0: 0.84, x1: -0.13, y1: 0.38, width: 0.1),
            .line(col.limb, x0: 0.11, y0: 0.84, x1: 0.15, y1: 0.48, width: 0.1),
            .box(col.limb, x: 0, y0: 1.01, w: 0.66, y1: 1.07, r: 0.03),
            .line(col.body, x0: -0.17, y0: 1.34, x1: -0.3, y1: 1.05, width: 0.09),
            .line(col.body, x0: 0.17, y0: 1.34, x1: 0.3, y1: 1.05, width: 0.09),
            .box(col.body, x: 0, y0: 0.8, w: 0.4, y1: 1.42, r: 0.13),
            .head(Palette.VRU.head, x: 0, y: 1.58, rx: 0.15, ry: 0.12),
        ])
        if tr.level >= 3 { pulseRing(&ctx, foot, u, 0.5, t) }
    }

    /// A pedestrian, standing: legs, body, arms, head.
    private static func person(_ ctx: inout GraphicsContext, _ tr: Track, _ t: Double) {
        let foot = Camera.pt(tr.x, tr.z)
        let u = foot.s * Palette.VRU.scale
        let col = Palette.vruColour(tr.level)
        groundShadow(&ctx, foot, u, 0.3)
        figure(&ctx, foot, u, [
            .line(col.limb, x0: -0.09, y0: 0.05, x1: -0.09, y1: 0.82, width: 0.12),
            .line(col.limb, x0: 0.09, y0: 0.05, x1: 0.09, y1: 0.82, width: 0.12),
            .line(col.body, x0: -0.27, y0: 1.36, x1: -0.3, y1: 0.9, width: 0.09),
            .line(col.body, x0: 0.27, y0: 1.36, x1: 0.3, y1: 0.9, width: 0.09),
            .box(col.body, x: 0, y0: 0.8, w: 0.44, y1: 1.44, r: 0.14),
            .head(Palette.VRU.head, x: 0, y: 1.62, rx: 0.13, ry: 0.13),
        ])
        if tr.level >= 3 { pulseRing(&ctx, foot, u, 0.45, t) }
    }

    /// Level 3 on a small target: a ring on the ground, because a red speck is easy to miss.
    private static func pulseRing(_ ctx: inout GraphicsContext, _ foot: Projected,
                                  _ u: Double, _ r: Double, _ t: Double) {
        let phase = (t * 2).truncatingRemainder(dividingBy: 1)
        let rr = (r + phase * 0.7) * u
        let rect = CGRect(x: foot.x - rr, y: foot.y - rr * 0.38, width: rr * 2, height: rr * 2 * 0.38)
        ctx.stroke(Path(ellipseIn: rect), with: .color(Palette.red.opacity(1 - phase)), lineWidth: 2.5)
    }

    /// The vehicle that answered a merge check with "no". Drawn on the ground around
    /// it, in the banner's own red, so the rider can see what stopped them rather than
    /// taking the answer on trust.
    static func blockedRing(_ ctx: inout GraphicsContext, _ tr: Track) {
        let p = Camera.pt(tr.x, tr.z)
        let (w, l) = World.size(tr.cls)
        let rx = max(p.s * max(w, l) * 0.72, 14)
        let rect = CGRect(x: p.x - rx, y: p.y - rx * 0.42, width: rx * 2, height: rx * 2 * 0.42)
        ctx.stroke(Path(ellipseIn: rect), with: .color(MergeBanner.blockedFill), lineWidth: 3.5)
        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 3.5, dy: 1.5)),
                   with: .color(.white.opacity(0.85)), lineWidth: 1.5)
    }

    /// You, as the navigation puck every map app uses: a chevron in a disc with a
    /// white collar, dead centre side to side.
    static func puck(_ ctx: inout GraphicsContext) {
        let p = Camera.pt(0, 0)
        // Big enough to find at a glance on a moving bike; the route runs in under it.
        let r = 2.4 * Camera.ppm(0)
        let k = r / 17                                   // the chevron was drawn for 17 pt
        var layer = ctx
        layer.addFilter(.shadow(color: Color(hex: 0x081830).opacity(0.45), radius: 5, y: 2))
        layer.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                   with: .color(Palette.text))

        let inner = r - 3.5 * k
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - inner, y: p.y - inner,
                                        width: inner * 2, height: inner * 2)),
                 with: .color(Palette.puck))

        var chevron = Path()
        chevron.move(to: CGPoint(x: p.x, y: p.y - 8 * k))
        chevron.addLine(to: CGPoint(x: p.x + 7.5 * k, y: p.y + 6.5 * k))
        chevron.addLine(to: CGPoint(x: p.x, y: p.y + 2.5 * k))
        chevron.addLine(to: CGPoint(x: p.x - 7.5 * k, y: p.y + 6.5 * k))
        chevron.closeSubpath()
        ctx.fill(chevron, with: .color(Palette.text))
    }
}

private extension StrokeStyle {
    func with(lineWidth: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: lineCap, lineJoin: lineJoin)
    }
}
