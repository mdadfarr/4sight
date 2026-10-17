import SwiftUI

/// The map layer of `docs/mock/front.html`: ground, road markings, the camera's
/// wedge, city blocks, parked cars and street labels. Ported call for call, so the
/// drawing order here matches the mock's `drawGround` / `drawBlocks` / `drawParked`.
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

    /// Rounded quad through four projected corners, the mock's `roundQuad`.
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

    /// Ground between two x values over a range of z. Straight lines stay straight.
    static func strip(_ x0: Double, _ x1: Double,
                      _ zA: Double = World.zFar, _ zB: Double = World.zNear) -> Path {
        poly([Camera.pt(x0, zA), Camera.pt(x1, zA), Camera.pt(x1, zB), Camera.pt(x0, zB)])
    }

    static func conePath() -> Path {
        let w = FOV.coneHalfWidth(FOV.zMax)
        return poly([Camera.pt(0, FOV.zMin), Camera.pt(-w, FOV.zMax), Camera.pt(w, FOV.zMax)])
    }

    // MARK: - Ground

    static func ground(_ ctx: inout GraphicsContext, _ t: Double) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: Design.width, height: Design.height)),
                 with: .color(Palette.ground))

        ctx.fill(strip(Road.farEdge, Road.kerb), with: .color(Palette.road))
        for (a, b) in World.spans(t, 0) {
            ctx.fill(strip(Road.kerb - 2.5, Road.kerb, a, b), with: .color(Palette.parkBay))
        }

        for st in World.streets {                       // cross streets, kerb to kerb
            let z = World.zOf(st.ahead, t)
            ctx.fill(strip(-160, 160, z - st.half, z + st.half), with: .color(Palette.road))
        }

        let lane = GraphicsContext.Shading.color(Palette.lane)
        for st in World.streets {
            let z = World.zOf(st.ahead, t)
            for zc in [z + st.half + 2, z - st.half - 2] {   // zebra crossings
                var x = Road.farEdge + 0.6
                while x < Road.kerb - 0.5 {
                    ctx.fill(poly(Camera.slab(x + 0.28, zc, 0.55, 3)), with: lane)
                    x += 1.15
                }
            }
            var x = -158.0                                   // cross-street centre line
            while x < 158 {
                if !(x > Road.farEdge - 4 && x < Road.kerb + 1) {
                    ctx.fill(poly(Camera.slab(x + 1.5, z, 3, 0.15)), with: lane)
                }
                x += 7
            }
            for ze in [z - st.half, z + st.half] {           // cross-street kerbs
                for (x0, x1) in [(-160.0, Road.farEdge), (Road.kerb, 160.0)] {
                    ctx.fill(poly([Camera.pt(x0, ze - 0.06), Camera.pt(x1, ze - 0.06),
                                   Camera.pt(x1, ze + 0.06), Camera.pt(x0, ze + 0.06)]), with: lane)
                }
            }
        }

        // Lane dashes, anchored to the road so they slide past at riding speed.
        for x in Road.dividers {
            var w = -80.0
            while w < 300 {
                let z1 = World.zOf(w, t), z0 = z1 - 3
                if !(z1 < World.zFar || z0 > World.zNear
                     || World.inStreet(z0, t, 3.6) || World.inStreet(z1, t, 3.6)) {
                    ctx.fill(poly(Camera.slab(x, (z0 + z1) / 2, 0.17, 3)), with: lane)
                }
                w += 7
            }
        }
        for (a, b) in World.spans(t, 0) {
            for x in [Road.kerb, Road.farEdge] {
                ctx.fill(poly([Camera.pt(x - 0.06, a), Camera.pt(x + 0.06, a),
                               Camera.pt(x + 0.06, b), Camera.pt(x - 0.06, b)]), with: lane)
            }
        }

        // What the rear camera covers, as a lighter wedge. The map around it is map
        // data, not camera, so it stays at full strength rather than being dimmed.
        let cone = conePath()
        ctx.fill(cone, with: .color(Palette.coneTint))
        ctx.stroke(cone, with: .color(Palette.cone), lineWidth: 1.5)
    }

    // MARK: - Blocks

    private static func blockWall(_ ax: Double, _ az: Double, _ bx: Double, _ bz: Double,
                                  _ h: Double) -> Path {
        poly([Camera.pt(ax, az), Camera.pt(bx, bz), Camera.pt(bx, bz, h), Camera.pt(ax, az, h)])
    }

    static func blocks(_ ctx: inout GraphicsContext, _ t: Double) {
        struct Live {
            let b: World.Block
            let zA, zB, near: Double
        }
        var live: [Live] = []
        for b in World.blocks {
            let zA = World.zOf(b.b, t), zB = World.zOf(b.a, t)     // zA is the far end
            if zB < World.zFar + 120 || zA > World.zNear - 5 { continue }
            live.append(Live(b: b, zA: zA, zB: zB,
                             near: Camera.pt((b.x0 + b.x1) / 2, (zA + zB) / 2).s))
        }
        live.sort { $0.near < $1.near }                            // far first

        for item in live {
            let b = item.b, zA = item.zA, zB = item.zB
            if b.park {
                let p = poly([Camera.pt(b.x0, zA), Camera.pt(b.x1, zA),
                              Camera.pt(b.x1, zB), Camera.pt(b.x0, zB)])
                ctx.fill(p, with: .color(Palette.park))
                ctx.stroke(p, with: .color(Palette.parkEdge), lineWidth: 1)
                continue
            }
            let edges: [(Double, Double, Double, Double)] = [
                (b.x0, zA, b.x1, zA), (b.x1, zA, b.x1, zB),
                (b.x1, zB, b.x0, zB), (b.x0, zB, b.x0, zA),
            ]
            let ordered = edges
                .map { w in (w, Camera.pt((w.0 + w.2) / 2, (w.1 + w.3) / 2).s) }
                .sorted { $0.1 < $1.1 }
            for (i, item2) in ordered.enumerated() {
                let w = item2.0
                ctx.fill(blockWall(w.0, w.1, w.2, w.3, b.h),
                         with: .color(i < 2 ? Palette.blockBack : Palette.blockSide))
            }
            ctx.fill(poly([Camera.pt(b.x0, zA, b.h), Camera.pt(b.x1, zA, b.h),
                           Camera.pt(b.x1, zB, b.h), Camera.pt(b.x0, zB, b.h)]),
                     with: .color(Palette.blockTop))
        }
    }

    /// Parked cars down the kerb. They are detections, so only where the camera sees them.
    static func parked(_ ctx: inout GraphicsContext, _ t: Double) {
        let spacing = 7.5
        var k = Int(floor((World.speed * t - 48) / spacing))
        while Double(k) * spacing < World.speed * t + 2 {
            defer { k += 1 }
            let z = World.zOf(Double(k) * spacing, t)
            if ((k % 4) + 4) % 4 == 3 { continue }              // the odd gap in the row
            if !FOV.seen(Road.parked, z, margin: 0.9) || World.inStreet(z, t, 3) { continue }
            let s = Camera.ppm(z)
            ctx.fill(poly(Camera.slab(Road.parked + 0.1, z + 0.1, 1.8, 4.5)),
                     with: .color(Palette.shadow))
            ctx.fill(roundQuad(Camera.slab(Road.parked, z, 1.8, 4.5, 0.9), max(2, 0.34 * s)),
                     with: .color(Palette.parkedBody))
            ctx.fill(roundQuad(Camera.slab(Road.parked, z + 0.3, 1.33, 2.0, 1.45), max(1.5, 0.22 * s)),
                     with: .color(Palette.parkedRoof))
        }
    }

    // MARK: - Labels and haze

    static func labels(_ ctx: inout GraphicsContext, _ t: Double) {
        for st in World.streets {
            let p = Camera.pt(-20, World.zOf(st.ahead, t))
            guard p.y >= Design.bannerH + 20, p.y <= Design.height - 120 else { continue }
            var resolved = ctx.resolve(Text(st.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded)))
            resolved.shading = .color(st.turn ? Palette.labelRoute : Palette.labelInk)
            let w = resolved.measure(in: CGSize(width: 300, height: 40)).width + 14
            var cx = min(max(p.x, w / 2 + 10), Design.width - w / 2 - 10)
            if p.y < Design.bannerH + 78 { cx = max(cx, 84 + w / 2) }   // clear the speed badge
            let box = CGRect(x: cx - w / 2, y: p.y - 11, width: w, height: 22)
            ctx.fill(Path(roundedRect: box, cornerRadius: 6), with: .color(Palette.label))
            ctx.draw(resolved, at: CGPoint(x: cx, y: p.y + 1), anchor: .center)
        }
    }

    /// Distance fades into the sky, the way the map apps do it.
    static func haze(_ ctx: inout GraphicsContext) {
        let rect = CGRect(x: 0, y: Design.bannerH, width: Design.width, height: 56)
        ctx.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Color(hex: 0xEEF1F5).opacity(0.85), Color(hex: 0xEEF1F5).opacity(0)]),
            startPoint: CGPoint(x: 0, y: Design.bannerH),
            endPoint: CGPoint(x: 0, y: Design.bannerH + 56)))
    }
}
