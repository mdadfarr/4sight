import MapKit
import Protocol
import SwiftUI

/// The live follow view: the real map, heading-up like Google Maps navigation. The puck
/// always points straight up, the map turns under it, and the route is the blue line.
/// What the rear camera saw is drawn on the map at true size, in the rider's frame.
///
/// The camera is driven from `LiveRoute` rather than MapKit's own heading follow, so the
/// map and the tracks placed on it turn by exactly the same eased heading.
struct LiveMapView: View {
    @ObservedObject var model: FrontModel

    /// Close enough that a car is a readable shape and footpaths draw, far enough to
    /// see the next turn. Tune outdoors.
    static let distance = 90.0
    static let pitch = 50.0
    /// The camera looks this far ahead of the rider, so the puck sits below centre with
    /// the rear wedge still on screen.
    static let lead = 12.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            let t = model.now(timeline.date)
            let h = model.route.heading(at: t)
            let rider = model.route.riderCoordinate(at: timeline.date)
            Map(position: .constant(camera(rider, h)), interactionModes: []) {
                let line = model.route.coordinates
                if line.count > 1 {
                    MapPolyline(coordinates: line)
                        .stroke(Palette.routeCase, style: Self.stroke(14))
                    MapPolyline(coordinates: line)
                        .stroke(Palette.routeCore, style: Self.stroke(9))
                }
                if let rider {
                    MapPolygon(coordinates: Self.wedge(rider, h))
                        .foregroundStyle(Palette.puck.opacity(0.08))
                        .stroke(Palette.puck.opacity(0.3), lineWidth: 1)
                    let blocker = MergeBanner.current(model.frame, link: model.link)?.blockedBy
                    ForEach(model.tracks(at: t), id: \.id) { tr in
                        if tr.id == blocker {
                            MapCircle(center: LiveRoute.offset(rider, x: tr.x, z: tr.z, heading: h),
                                      radius: max(World.size(tr.cls).l, 2) * 0.75)
                                .foregroundStyle(.clear)
                                .stroke(MergeBanner.blockedFill, lineWidth: 3.5)
                        }
                        if tr.cls == "person" || tr.cls == "bicycle" {
                            // Drawn larger than life: a 0.6 m person is a few points across.
                            MapCircle(center: LiveRoute.offset(rider, x: tr.x, z: tr.z, heading: h),
                                      radius: 0.9)
                                .foregroundStyle(Palette.vruColour(tr.level).body.opacity(tr.opacity))
                                .stroke(.white.opacity(tr.opacity), lineWidth: 2)
                        } else {
                            MapPolygon(coordinates: Self.footprint(tr, rider, h))
                                .foregroundStyle(Palette.paint(tr.level).body.opacity(tr.opacity))
                                .stroke(Palette.paint(tr.level).edge.opacity(tr.opacity), lineWidth: 1.5)
                        }
                    }
                    Annotation("", coordinate: rider, anchor: .center) { Self.puck }
                } else {
                    UserAnnotation()
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls { }
            .environment(\.colorScheme, .light)
        }
        .ignoresSafeArea()
    }

    private func camera(_ rider: CLLocationCoordinate2D?, _ h: Double) -> MapCameraPosition {
        guard let rider else { return .userLocation(followsHeading: true, fallback: .automatic) }
        return .camera(MapCamera(centerCoordinate: LiveRoute.offset(rider, x: 0, z: -Self.lead, heading: h),
                                 distance: Self.distance, heading: h, pitch: Self.pitch))
    }

    private static func stroke(_ width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    /// What the rear camera covers, the same wedge the scripted view shades.
    private static func wedge(_ rider: CLLocationCoordinate2D, _ h: Double) -> [CLLocationCoordinate2D] {
        let w = FOV.coneHalfWidth(FOV.zMax)
        return [rider, LiveRoute.offset(rider, x: -w, z: FOV.zMax, heading: h),
                LiveRoute.offset(rider, x: w, z: FOV.zMax, heading: h)]
    }

    /// A vehicle's footprint at true size, its long side along the rider's direction.
    private static func footprint(_ tr: VehicleSprite.Track, _ rider: CLLocationCoordinate2D,
                                  _ h: Double) -> [CLLocationCoordinate2D] {
        let (w, l) = World.size(tr.cls)
        return [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { sx, sz in
            LiveRoute.offset(rider, x: tr.x + sx * w / 2, z: tr.z + sz * l / 2, heading: h)
        }
    }

    /// You: the navigation puck every map app uses. Annotations stay upright on screen,
    /// and the map is heading-up, so the arrow always points the way the rider faces.
    private static var puck: some View {
        ZStack {
            Circle().fill(Palette.text).frame(width: 34, height: 34)
            Circle().fill(Palette.puck).frame(width: 27, height: 27)
            Image(systemName: "location.north.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.text)
        }
        .shadow(color: Color(hex: 0x081830).opacity(0.45), radius: 5, y: 2)
    }
}
