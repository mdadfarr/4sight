import SwiftUI

/// The route, as a blue ribbon that turns where you will turn. Ported from the
/// mock's `ribbon` / `drawRoute`.
enum RouteRibbon {

    /// A ribbon w metres wide along a ground polyline, projected edge by edge, so it
    /// narrows with distance the way the surface does.
    static func path(_ line: [(Double, Double)], width w: Double) -> Path {
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in line.indices {
            let (x, z) = line[i]
            let (ax, az) = line[max(i - 1, 0)]
            let (bx, bz) = line[min(i + 1, line.count - 1)]
            let dx = bx - ax, dz = bz - az
            let n = max(hypot(dx, dz), 0.0001)
            let nx = -dz / n * w / 2, nz = dx / n * w / 2
            left.append(Camera.pt(x + nx, z + nz).cg)
            right.append(Camera.pt(x - nx, z - nz).cg)
        }
        var p = Path()
        guard let first = left.first else { return p }
        p.move(to: first)
        for q in left.dropFirst() { p.addLine(to: q) }
        for q in right.reversed() { p.addLine(to: q) }
        p.closeSubpath()
        return p
    }

    static func draw(_ ctx: inout GraphicsContext, _ t: Double) {
        draw(&ctx, line: World.routeLine(t))
    }

    static func draw(_ ctx: inout GraphicsContext, line: [(Double, Double)]) {
        guard line.count > 1 else { return }
        ctx.fill(path(line, width: 2.1), with: .color(Palette.routeCase))
        ctx.fill(path(line, width: 1.5), with: .color(Palette.routeCore))

        // The road already ridden, fading out behind: it marks the path taken without
        // painting over the stretch the warnings are about.
        let a = Camera.pt(-0.75, 0.4), b = Camera.pt(0.75, 0.4)
        let c = Camera.pt(0.75, 22), d = Camera.pt(-0.75, 22)
        ctx.fill(SceneRenderer.poly([a, b, c, d]), with: .linearGradient(
            Gradient(colors: [Palette.routeCore.opacity(0.55), Palette.routeCore.opacity(0)]),
            startPoint: CGPoint(x: 0, y: a.y), endPoint: CGPoint(x: 0, y: c.y)))
    }
}
