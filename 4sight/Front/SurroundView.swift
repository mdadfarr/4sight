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
                draw(&c, t: t, date: timeline.date)
            }
        }
        .background(Palette.ground)
    }

    /// The scripted ride keeps the mock's whole invented street. The live feed draws the
    /// real streets around the rider from OpenStreetMap (`StreetRenderer`).
    private func draw(_ ctx: inout GraphicsContext, t: Double, date: Date) {
        if model.scripted {
            SceneRenderer.ground(&ctx, t)
            SceneRenderer.blocks(&ctx, t)
            RouteRibbon.draw(&ctx, t)
            SceneRenderer.parked(&ctx, t)
        } else {
            StreetRenderer.draw(&ctx, map: StreetMap.bundled, rider: model.route.riderCoordinate(at: date),
                                heading: model.route.heading(at: t), route: model.route.coordinates,
                                plan: model.lanePlan)
        }
        let blocker = MergeBanner.current(model.frame, link: model.link)?.blockedBy
        let rider = model.scripted ? nil : model.route.riderCoordinate(at: date)
        for var track in model.tracks(at: t) {
            if track.oncoming, let lane = StreetRenderer.oncomingLane(
                map: StreetMap.bundled, rider: rider, heading: model.route.heading(at: t), x: track.x, z: track.z) {
                track = VehicleSprite.Track(id: track.id, cls: track.cls, x: lane, z: track.z, level: track.level,
                                            turnR: track.turnR, opacity: track.opacity, oncoming: true)
            }
            var c = ctx
            c.opacity = track.opacity
            if track.id == blocker { VehicleSprite.blockedRing(&c, track) }
            VehicleSprite.draw(&c, track, t)
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
    /// A vehicle on the rider's left pulling away faster than the rider rides is going the
    /// other way: it passed and is leaving. A parked car recedes at exactly riding speed,
    /// so the 3 m/s margin keeps it out.
    static func oncoming(_ tr: TrackMessage, riderSpeed: Double) -> Bool {
        guard ![.person, .bicycle].contains(tr.cls), tr.x < -1.5 else { return false }
        return tr.z * tr.invTTC < -(riderSpeed + 3)
    }

    static func visibleTracks(_ frame: FrameMessage?) -> [VehicleSprite.Track] {
        guard let frame else { return [] }
        return frame.tracks
            .filter { FOV.seen($0.x, $0.z, margin: World.size($0.cls.rawValue).w / 2) }
            .sorted { $0.z < $1.z }
            .map { tr in
                let vru = tr.cls == .person || tr.cls == .bicycle
                return VehicleSprite.Track(
                    id: tr.id, cls: tr.cls.rawValue, x: tr.x, z: tr.z,
                    level: vru && !frame.demo ? 0 : tr.level, turnR: tr.turnR,
                    oncoming: oncoming(tr, riderSpeed: frame.speed))
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
