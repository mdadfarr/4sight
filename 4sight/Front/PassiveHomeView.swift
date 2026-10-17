import Links
import MapKit
import SwiftUI

/// What the rider sees at a standstill: where they are, and the shortest path to
/// setting off. Apple Maps' shape — map behind, a sheet of search and saved places —
/// with the pair state the two-phone part of this product needs.
struct PassiveHomeView: View {
    @ObservedObject var model: FrontModel
    @ObservedObject var flow: RideFlow
    let onPick: (MKMapItem) -> Void

    /// Falling back to `.automatic` with no fix yet shows the whole continent, which
    /// tells the rider nothing; the city is a better guess than the hemisphere.
    @AppStorage(PeerFeed.nameKey) private var frontName = ""
    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(
        MKCoordinateRegion(center: .init(latitude: 43.6605, longitude: -79.4280),
                           span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))))

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera) { UserAnnotation() }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .ignoresSafeArea()

            sheet
        }
        .background(Theme.bg)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Theme.line)
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 9).padding(.bottom, 14)

            Button { flow.picking = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    Text("Where to?")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .frame(height: 48)
                .padding(.horizontal, 14)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 12))
            }

            LinkStrip(link: model.link).padding(.top, 14)
            nameField.padding(.top, 10)

            if flow.recents.items.isEmpty {
                Text("Nowhere yet. Search for somewhere to go, and it will wait here next time.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
            } else {
                Text("Recents")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 22).padding(.bottom, 6)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(flow.recents.items) { place in
                            Button { onPick(place.mapItem) } label: { row(place) }
                            Divider().overlay(Theme.line)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        .ignoresSafeArea(edges: .bottom)
    }

    /// What the rear phone's `-peer` argument has to match. iOS hands out a generic
    /// "iPhone" without the device-name entitlement, so on real hardware this is the
    /// only way to tell two 4sight bikes apart.
    private var nameField: some View {
        HStack(spacing: 10) {
            Text("This phone")
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(Theme.textDim)
            TextField(PeerLink.deviceName, text: $frontName)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { model.restartFeed() }
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 11))
    }

    private func row(_ place: RecentPlace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textDim)
                .frame(width: 34, height: 34)
                .background(Theme.ground, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                if !place.subtitle.isEmpty {
                    Text(place.subtitle)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .frame(minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }
}
