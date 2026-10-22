import SwiftUI

/// Ground ribbons: the route, roads and paths, drawn as strips that narrow with distance.
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
}
