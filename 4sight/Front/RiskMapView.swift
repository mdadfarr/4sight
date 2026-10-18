import CoreLocation
import MapKit
import SwiftUI

/// Where the alerts fired. Near-miss points over a 250 m density grid, with the
/// ridden route under them. Reads Documents/events.jsonl; nothing leaves the phone
/// unless the rider taps Share. Under them, Toronto's public close-pass layer when the
/// city server is set (CityAPI.base), and the City's bike lanes and cyclist KSI sites.
struct RiskMapView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = EventStore()
    @State private var camera: MapCameraPosition = .region(Self.region(for: []))
    @State private var city: CityLayer?
    @State private var showCity = true
    let demo: Bool

    var body: some View {
        Map(position: $camera) {
            if showCity, let ctx = CityContext.bundled {
                ForEach(ctx.lanes) { lane in
                    MapPolyline(coordinates: lane.points)
                        .stroke((lane.protected ? Light.green : Light.blue).opacity(0.55), lineWidth: 2)
                }
            }
            ForEach(city?.segments ?? []) { seg in
                MapPolyline(seg.line).stroke(Self.rateTint(seg.per100km), lineWidth: 4)
            }
            ForEach(city?.passes ?? []) { pass in
                Annotation(coordinate: pass.coordinate) {
                    Circle().fill(pass.level >= 3 ? Light.red : Light.amber).opacity(0.7).frame(width: 6, height: 6)
                } label: { EmptyView() }
            }
            if showCity, let ctx = CityContext.bundled {
                ForEach(ctx.ksi) { k in
                    Annotation(coordinate: k.coordinate) {
                        Circle().fill(Light.ink).opacity(0.75)
                            .frame(width: k.killed ? 9 : 6, height: k.killed ? 9 : 6)
                            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
                    } label: { EmptyView() }
                }
            }
            ForEach(store.cells) { cell in
                MapPolygon(coordinates: cell.corners)
                    .foregroundStyle(Self.cellTint(cell))
                    .stroke(Light.line.opacity(0.5), lineWidth: 0.5)
            }
            ForEach(store.tracks) { track in
                MapPolyline(coordinates: track.points)
                    .stroke(Light.dim.opacity(0.55), lineWidth: 3)
            }
            ForEach(store.events) { event in
                if let c = event.coordinate {
                    Annotation(coordinate: c) { dot(for: event) } label: { EmptyView() }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .preferredColorScheme(.light)
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) { closeButton }
        .overlay(alignment: .bottom) { summary }
        .onAppear {
            store.load(demo: demo)
            camera = .region(Self.region(for: store.events))
        }
        .task { city = await CityLayer.load() }
    }

    // MARK: - Pieces

    private func dot(for event: RiskEvent) -> some View {
        Circle()
            .fill(event.level >= 3 ? Light.red : Light.amber)
            .frame(width: event.level >= 3 ? 13 : 10, height: event.level >= 3 ? 13 : 10)
            .overlay(Circle().stroke(Light.sheet.opacity(0.85), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Light.ink)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.92), in: Circle())
        }
        .padding(.leading, 16)
        .padding(.top, 60)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 26) {
                stat("\(store.events.count)", "near misses")
                stat("\(store.levelThreeCount)", "imminent")
                if let perKm = store.eventsPerKm {
                    stat(String(format: "%.1f", perKm), "per km")
                }
                Spacer(minLength: 0)
            }
            if CityContext.bundled != nil {
                Toggle(isOn: $showCity) {
                    Text("City of Toronto: protected (green) and painted (blue) lanes; black dots, cyclists killed or seriously injured 2022\u{2013}26")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Light.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Light.blue)
            }
            if city?.synthetic == true {
                Text("Includes example data, not real rides yet")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Light.dim)
            }
            if store.events.isEmpty {
                Text("No events logged yet. Ride with the rear phone recording, or relaunch with --demoevents.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Light.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else if store.hasFile {
                ShareLink(item: EventStore.eventsURL) {
                    Label("Share events", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Light.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Light.line.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Light.sheet.opacity(0.94))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        .ignoresSafeArea(edges: .bottom)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Light.ink)
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Light.dim)
        }
    }

    // MARK: - Styling

    /// City streets by close passes per 100 km ridden. shortcut: fixed cut-offs at 10 and
    /// 30; rescale once real Toronto numbers show the spread.
    static func rateTint(_ per100km: Double) -> Color {
        (per100km >= 30 ? Light.red : per100km >= 10 ? Light.amber : Light.faint).opacity(0.85)
    }

    /// Denser cells read stronger; a cell holding any level 3 goes red.
    static func cellTint(_ cell: GridCell) -> Color {
        let weight = min(0.14 + Double(cell.count) * 0.055, 0.42)
        return (cell.worstLevel >= 3 ? Light.red : Light.amber).opacity(weight)
    }

    /// Frames every located event with a margin; falls back to downtown Toronto.
    static func region(for events: [RiskEvent]) -> MKCoordinateRegion {
        let pts = events.compactMap(\.coordinate)
        guard let first = pts.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 43.6605, longitude: -79.4280),
                                      span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for p in pts {
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.006),
                                   longitudeDelta: max((maxLon - minLon) * 1.15, 0.006)))
    }
}
