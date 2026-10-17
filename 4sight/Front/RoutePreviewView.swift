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
        .background(Theme.bg)
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
                    Circle().fill(Theme.red)
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
                        .foregroundStyle(Theme.text)
                        .frame(width: 40, height: 40)
                        .background(Theme.bg.opacity(0.92), in: Circle())
                }
                Spacer()
            }
            Spacer()
        }
        .padding(.leading, 16).padding(.top, 8)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Theme.line)
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
                    .background(watched ? Palette.routeCore : Theme.red,
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(chosen == nil)

            if !watched {
                Text("Navigation only. Nothing behind you is being watched.")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 9)
            }

            LinkStrip(link: model.link).padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 26)
        .background(Theme.bg)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        .ignoresSafeArea(edges: .bottom)
    }

    private func option(_ plan: RoutePlan) -> some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(plan.minutes) min")
                    .font(.system(size: 21, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.text)
                Text(plan.name.isEmpty ? plan.distanceText : "\(plan.distanceText) · \(plan.name)")
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(Theme.textDim)
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
            .stroke(plan == chosen ? Palette.routeCore : Theme.line, lineWidth: 2))
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
