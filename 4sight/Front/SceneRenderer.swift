import SwiftUI

/// Drawing helpers shared by the street, the route and the vehicles.
enum SceneRenderer {

    // MARK: - Path helpers

    static func poly(_ pts: [Projected]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first.cg)
        for q in pts.dropFirst() { p.addLine(to: q.cg) }
        p.closeSubpath()
        return p
    }

    /// Rounded quad through four projected corners.
    static func roundQuad(_ p: [Projected], _ r: Double) -> Path {
        func mid(_ a: Projected, _ b: Projected) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        var path = Path()
        path.move(to: mid(p[0], p[1]))
        for i in 1...4 {
            path.addArc(tangent1End: p[i % 4].cg,
                        tangent2End: mid(p[i % 4], p[(i + 1) % 4]), radius: r)
        }
        path.closeSubpath()
        return path
    }

    /// Distance fades into the sky, the way the map apps do it.
    static func haze(_ ctx: inout GraphicsContext) {
        // The guidance card floats, so the far map shows around it: fade it out toward
        // the top behind the card and the status bar.
        let rect = CGRect(x: 0, y: 0, width: Design.width, height: GuidanceCard.bottom + 50)
        ctx.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Color(hex: 0xEEF1F5).opacity(0.95), Color(hex: 0xEEF1F5).opacity(0)]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 0, y: rect.maxY)))
    }
}
