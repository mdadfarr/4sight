import CoreLocation
import MapKit
import SwiftUI

/// Where the alerts fired. Near-miss points over a 250 m density grid, with the
/// ridden route under them. Reads Documents/events.jsonl; nothing leaves the phone
/// unless the rider taps Share.
struct RiskMapView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = EventStore()
    let demo: Bool

    var body: some View {
        Map(initialPosition: .region(Self.region(for: store.events))) {
            ForEach(store.cells) { cell in
                MapPolygon(coordinates: cell.corners)
                    .foregroundStyle(Self.cellTint(cell))
                    .stroke(Theme.line.opacity(0.5), lineWidth: 0.5)
            }
            ForEach(store.tracks) { track in
                MapPolyline(coordinates: track.points)
                    .stroke(Theme.textDim.opacity(0.55), lineWidth: 3)
            }
            ForEach(store.events) { event in
                if let c = event.coordinate {
                    Annotation(coordinate: c) { dot(for: event) } label: { EmptyView() }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) { closeButton }
        .overlay(alignment: .bottom) { summary }
        .onAppear { store.load(demo: demo) }
    }

    // MARK: - Pieces

    private func dot(for event: RiskEvent) -> some View {
        Circle()
            .fill(event.level >= 3 ? Theme.red : Theme.amber)
            .frame(width: event.level >= 3 ? 13 : 10, height: event.level >= 3 ? 13 : 10)
            .overlay(Circle().stroke(Theme.bg.opacity(0.85), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 40, height: 40)
                .background(Theme.ground.opacity(0.92), in: Circle())
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
            if store.events.isEmpty {
                Text("No events logged yet. Ride with the rear phone recording, or relaunch with --demoevents.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else if store.hasFile {
                ShareLink(item: EventStore.eventsURL) {
                    Label("Share events", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.line.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg.opacity(0.94))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        .ignoresSafeArea(edges: .bottom)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.text)
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.textDim)
        }
    }

    // MARK: - Styling

    /// Denser cells read stronger; a cell holding any level 3 goes red.
    static func cellTint(_ cell: GridCell) -> Color {
        let weight = min(0.14 + Double(cell.count) * 0.055, 0.42)
        return (cell.worstLevel >= 3 ? Theme.red : Theme.amber).opacity(weight)
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
                                   longitudeDelta: max((maxLon - minLon) * 1.4, 0.006)))
    }
}
