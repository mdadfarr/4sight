import MapKit
import SwiftUI

/// The last screen before the wheels move: the way there drawn, the alternatives
/// MapKit offers, and one button.
///
/// The button names what the rider is about to get. Starting with no rear phone is
/// allowed — a safety app that refuses to open gets deleted the first time Bluetooth
/// misbehaves — but it is never described as the thing it is not.
struct RoutePreviewView: View {
    @ObservedObject var model: FrontModel
    let plans: [RoutePlan]
    let destination: String
    @Binding var chosen: RoutePlan?
    let onStart: (RoutePlan) -> Void
    let onCancel: () -> Void

    private var watched: Bool { model.link == .connected }

    var body: some View {
        ZStack(alignment: .bottom) {
            map.ignoresSafeArea()
            sheet
            closeButton
        }
        .background(Light.sheet)
    }

    private var map: some View {
        Map(initialPosition: .region(Self.region(plans))) {
            ForEach(plans) { plan in
                MapPolyline(coordinates: plan.coordinates)
                    .stroke(plan == chosen ? Palette.routeCore : Palette.routeCase,
                            style: StrokeStyle(lineWidth: plan == chosen ? 7 : 5,
                                               lineCap: .round, lineJoin: .round))
            }
            if let end = chosen?.coordinates.last {
                Annotation(destination, coordinate: end) {
                    Circle().fill(Light.red)
                        .frame(width: 15, height: 15)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Light.ink)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.95), in: Circle())
                        .shadow(color: Light.shadow, radius: 6, y: 2)
                }
                Spacer()
            }
            Spacer()
        }
        .padding(.leading, 16).padding(.top, 8)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Light.handle)
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 9).padding(.bottom, 14)

            ForEach(plans) { plan in
                Button { chosen = plan } label: { option(plan) }
                    .padding(.bottom, 9)
            }

            Button { if let chosen { onStart(chosen) } } label: {
                Text(watched ? "Start ride" : "Ride without rear view")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(watched ? Palette.routeCore : Light.red,
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(chosen == nil)

            if !watched {
                Text("Navigation only. Nothing behind you is being watched.")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Light.red)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 9)
            }

            LinkStrip(model: model).padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 26)
        .background(Light.sheet)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        .ignoresSafeArea(edges: .bottom)
    }

    private func option(_ plan: RoutePlan) -> some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(plan.minutes) min")
                    .font(.system(size: 21, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Light.ink)
                Text(plan.name.isEmpty ? plan.distanceText : "\(plan.distanceText) · \(plan.name)")
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(Light.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if plan == chosen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.routeCore)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(plan == chosen ? Palette.routeCore.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .stroke(plan == chosen ? Palette.routeCore : Light.line, lineWidth: 2))
        .contentShape(Rectangle())
    }

    /// Frames every offered route with a margin.
    static func region(_ plans: [RoutePlan]) -> MKCoordinateRegion {
        let pts = plans.flatMap(\.coordinates)
        guard let first = pts.first else {
            return MKCoordinateRegion(center: .init(latitude: 43.6605, longitude: -79.4280),
                                      span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for p in pts {
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        return MKCoordinateRegion(
            center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.9, 0.006),
                                   longitudeDelta: max((maxLon - minLon) * 1.3, 0.006)))
    }
}

/// What the route sheet will look like, while MapKit works out the routes: the same
/// card, with grey bars where the times will be, so the screen does not jump when they
/// arrive and the rider can see something is coming.
struct RoutePreviewSkeleton: View {
    @State private var dim = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                Capsule().fill(Light.handle).frame(width: 38, height: 5)
                    .frame(maxWidth: .infinity).padding(.top, 9).padding(.bottom, 5)
                ForEach(0..<2, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        bar(width: 80, height: 18)
                        bar(width: i == 0 ? 170 : 140, height: 12)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                }
                RoundedRectangle(cornerRadius: 14).fill(Light.field).frame(height: 52)
                bar(width: .infinity, height: 44, radius: 12).padding(.top, 3)
            }
            .padding(.horizontal, 18).padding(.bottom, 34)
            .background(Light.sheet)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
            .opacity(dim ? 0.55 : 1)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { dim = true } }
        .accessibilityLabel("Finding routes")
    }

    private func bar(width: CGFloat, height: CGFloat, radius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: radius).fill(Light.field)
            .frame(maxWidth: width == .infinity ? .infinity : width).frame(height: height)
    }
}
