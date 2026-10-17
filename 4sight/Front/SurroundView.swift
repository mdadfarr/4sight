import SwiftUI
import Protocol

/// Top-down rear view. Ground exists only inside the camera wedge (±35°, 40 m).
struct SurroundView: View {
    @ObservedObject var model: FrontModel

    static let halfAngle = 35.0 * .pi / 180
    static let range = 40.0
    static let bikeInset: CGFloat = 24

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / 20)) { timeline in
            let t = model.now(timeline.date)
            Canvas { ctx, size in
                let apex = CGPoint(x: size.width / 2, y: size.height - Self.bikeInset)
                let scale = Self.scale(for: size)
                let wedge = Self.sector(apex: apex, radius: Self.range * scale)
                ctx.fill(wedge, with: .color(Theme.ground))
                ctx.clip(to: wedge)
                for r in [10.0, 20.0, 30.0] {
                    ctx.stroke(Self.arc(apex: apex, radius: r * scale), with: .color(Theme.line), lineWidth: 1)
                }
                for x in [-1.5, 1.5] {
                    var p = Path()
                    p.move(to: CGPoint(x: apex.x + x * scale, y: apex.y))
                    p.addLine(to: CGPoint(x: apex.x + x * scale, y: apex.y - Self.range * scale))
                    ctx.stroke(p, with: .color(Theme.line), lineWidth: 1)
                }
                // Far tracks first so near ones draw on top.
                for track in (model.frame?.tracks ?? []).sorted(by: { $0.z > $1.z }) {
                    guard let m = model.motions[track.id] else { continue }
                    let pos = model.position(of: m, at: t)
                    let centre = CGPoint(x: apex.x + pos.x * scale, y: apex.y - pos.y * scale)
                    TrackGlyph.draw(track, at: centre, z: pos.y, scale: scale, t: t, in: &ctx)
                }
            }
            .overlay(alignment: .bottom) {
                Image(systemName: "bicycle")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .frame(height: Self.bikeInset * 2)
            }
        }
        .background(Theme.bg)
    }

    /// Points per metre so 40 m reaches the top of the band; the wedge's far corners may leave the screen.
    static func scale(for size: CGSize) -> CGFloat {
        (size.height - bikeInset - 12) / range
    }

    static func sector(apex: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        p.move(to: apex)
        p.addArc(center: apex, radius: radius,
                 startAngle: .radians(-.pi / 2 - halfAngle), endAngle: .radians(-.pi / 2 + halfAngle),
                 clockwise: false)
        p.closeSubpath()
        return p
    }

    static func arc(apex: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        p.addArc(center: apex, radius: radius,
                 startAngle: .radians(-.pi / 2 - halfAngle), endAngle: .radians(-.pi / 2 + halfAngle),
                 clockwise: false)
        return p
    }
}
