import SwiftUI
import Protocol

/// Draws one track as a flat two-tone silhouette coloured by threat level.
enum TrackGlyph {
    /// Footprint in metres (width, length) per class.
    static func footprint(_ cls: VehicleClass) -> CGSize {
        switch cls {
        case .car: CGSize(width: 1.8, height: 4.5)
        case .truck, .bus: CGSize(width: 2.5, height: 10)
        case .motorcycle: CGSize(width: 0.8, height: 2.2)
        case .bicycle: CGSize(width: 0.6, height: 1.8)
        case .person: CGSize(width: 0.6, height: 0.6)
        }
    }

    static func draw(_ track: TrackMessage, at centre: CGPoint, z: Double, scale: CGFloat,
                     t: Double, in ctx: inout GraphicsContext) {
        // Perspective cue: far glyphs shrink to 65 % of their true footprint.
        let persp = 1 - 0.35 * min(max(z / SurroundView.range, 0), 1)
        let fp = footprint(track.cls)
        let w = fp.width * scale * persp, h = fp.height * scale * persp
        let rect = CGRect(x: centre.x - w / 2, y: centre.y - h / 2, width: w, height: h)

        let fill: Color = switch track.level { case 3: Theme.red; case 2: Theme.amber; default: Theme.silhouette }
        let detail: Color = track.level >= 2 ? Theme.bg.opacity(0.35) : Theme.edge
        let body = bodyPath(track.cls, in: rect)
        ctx.fill(body, with: .color(fill))
        switch track.level {
        case 1: ctx.stroke(body, with: .color(Theme.amber), lineWidth: 2)
        case 0: ctx.stroke(body, with: .color(detail), lineWidth: 1)
        default: break
        }
        ctx.fill(detailPath(track.cls, in: rect), with: .color(detail))

        if track.level == 3 {
            // 1 Hz pulse, radius grows by up to 8 pt.
            let r = max(w, h) / 2 + 4 + 8 * pulse(t)
            ctx.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(Theme.red), lineWidth: 2)
        }
        if track.level == 2 {
            drawOutlined(Text("THREAT").font(.system(size: 13, weight: .bold, design: .rounded)),
                         colour: Theme.amber, at: CGPoint(x: centre.x, y: rect.maxY + 10), in: &ctx)
        }
        if track.turnR {
            drawOutlined(Text(Image(systemName: "arrow.turn.up.right")).font(.system(size: 14, weight: .bold)),
                         colour: Theme.amber, at: CGPoint(x: rect.maxX + 10, y: centre.y), in: &ctx)
        }
    }

    /// 0…1 at 1 Hz on the UI clock; shared by the ring and the edge glow.
    static func pulse(_ t: Double) -> Double { 0.5 + 0.5 * sin(2 * .pi * t) }

    /// Screen-up is +z (further behind the bike); the end nearest the bike is rect.maxY.
    static func bodyPath(_ cls: VehicleClass, in r: CGRect) -> Path {
        switch cls {
        case .car: Path(roundedRect: r, cornerRadius: r.width * 0.3)
        case .truck, .bus: Path(roundedRect: r, cornerRadius: r.width * 0.15)
        case .motorcycle, .bicycle: Path(roundedRect: r, cornerRadius: r.width / 2)
        case .person:
            Path(ellipseIn: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.width * 0.55))
                .union(Path(roundedRect: CGRect(x: r.midX - r.width * 0.3, y: r.minY + r.width * 0.45,
                                                width: r.width * 0.6, height: r.height - r.width * 0.45),
                            cornerRadius: r.width * 0.3))
        }
    }

    /// Lighter/darker second tone: roof, cab line, wheels, head.
    static func detailPath(_ cls: VehicleClass, in r: CGRect) -> Path {
        switch cls {
        case .car:
            let w = r.width * 0.6
            return Path(roundedRect: CGRect(x: r.midX - w / 2, y: r.minY + r.height * 0.08,
                                            width: w, height: r.height * 0.3), cornerRadius: w * 0.25)
        case .truck, .bus:
            return Path(CGRect(x: r.minX + r.width * 0.1, y: r.maxY - r.height * 0.12,
                               width: r.width * 0.8, height: 1.5))
        case .motorcycle, .bicycle:
            let d = r.width * 0.5
            var p = Path(ellipseIn: CGRect(x: r.midX - d / 2, y: r.minY + d * 0.3, width: d, height: d))
            p.addEllipse(in: CGRect(x: r.midX - d / 2, y: r.maxY - d * 1.3, width: d, height: d))
            return p
        case .person:
            let d = r.width * 0.4
            return Path(ellipseIn: CGRect(x: r.midX - d / 2, y: r.minY + d * 0.15, width: d, height: d))
        }
    }

    /// Text with a 1 pt dark outline so it survives sunlight.
    static func drawOutlined(_ text: Text, colour: Color, at p: CGPoint, in ctx: inout GraphicsContext) {
        for (dx, dy) in [(-1.0, 0.0), (1, 0), (0, -1), (0, 1)] {
            ctx.draw(text.foregroundColor(Theme.bg), at: CGPoint(x: p.x + dx, y: p.y + dy))
        }
        ctx.draw(text.foregroundColor(colour), at: p)
    }
}
