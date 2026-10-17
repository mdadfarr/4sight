import Protocol
import SwiftUI

/// The follow view: one pinhole camera behind and above the rider, drawing the map
/// around them and whatever the rear camera saw inside its wedge.
///
/// Everything is laid out in the mock's 393 x 852 design space and scaled once, so
/// the constants in `Camera`, `Road` and `World` stay the numbers from
/// `docs/mock/front.html`.
struct SurroundView: View {
    @ObservedObject var model: FrontModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { ctx, size in
                let t = model.now(timeline.date)
                let scale = size.width / Design.width
                var c = ctx
                c.scaleBy(x: scale, y: scale)
                draw(&c, t: t)
            }
        }
        .background(Palette.ground)
    }

    /// The scripted ride keeps the mock's whole invented street. The live feed gets only
    /// what is real: the road, the route the rider chose, and what the rear camera saw.
    private func draw(_ ctx: inout GraphicsContext, t: Double) {
        if model.scripted {
            SceneRenderer.ground(&ctx, t)
            SceneRenderer.blocks(&ctx, t)
            RouteRibbon.draw(&ctx, t)
            SceneRenderer.parked(&ctx, t)
        } else {
            SceneRenderer.road(&ctx, travelled: model.travelled)
            RouteRibbon.draw(&ctx, line: model.route.line(at: t))
        }
        let blocker = MergeBanner.current(model.frame, link: model.link)?.blockedBy
        for track in model.tracks(at: t) {
            if track.id == blocker { VehicleSprite.blockedRing(&ctx, track) }
            VehicleSprite.draw(&ctx, track, t)
        }
        VehicleSprite.puck(&ctx)
        SceneRenderer.haze(&ctx)
        if model.scripted { SceneRenderer.labels(&ctx, t) }
    }

    /// Only what the rear camera can actually see, painted far-behind last because
    /// that is what sits nearest the lens. Half a vehicle width of margin, so a car
    /// counts as in view as soon as part of it is.
    ///
    /// Vulnerable road users stay grey unless the frame is in demo mode, matching
    /// ThreatEngine, which ignores bicycles and people outside it.
    static func visibleTracks(_ frame: FrameMessage?) -> [VehicleSprite.Track] {
        guard let frame else { return [] }
        return frame.tracks
            .filter { FOV.seen($0.x, $0.z, margin: World.size($0.cls.rawValue).w / 2) }
            .sorted { $0.z < $1.z }
            .map { tr in
                let vru = tr.cls == .person || tr.cls == .bicycle
                return VehicleSprite.Track(
                    id: tr.id, cls: tr.cls.rawValue, x: tr.x, z: tr.z,
                    level: vru && !frame.demo ? 0 : tr.level, turnR: tr.turnR)
            }
    }
}

/// The screen-edge warning, kept in its own layer so it paints over the nav chrome
/// as well as the map: a warning outranks everything else on screen.
struct AlertOverlay: View {
    @ObservedObject var model: FrontModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { ctx, size in
                var c = ctx
                AlertBands.draw(&c, history: model.alerts,
                                now: model.now(timeline.date), canvas: size)
            }
        }
        .allowsHitTesting(false)
    }
}
