import Links
import MapKit
import Protocol
import SwiftUI

/// What the rider sees at a standstill, in Apple Maps' shape: the map, a pill saying
/// whether the bike is awake (rear camera and grips), and a sheet of search, places
/// and recents. Pulled up (or the bike button), the sheet adds the bike's detail,
/// this phone's pairing name and the close-pass map.
struct PassiveHomeView: View {
    @ObservedObject var model: FrontModel
    @ObservedObject var flow: RideFlow
    let onPick: (MKMapItem) -> Void
    var onDemo: () -> Void = {}
    var onRiskMap: () -> Void = {}

    /// Falling back to `.automatic` with no fix yet shows the whole continent, which
    /// tells the rider nothing; the city is a better guess than the hemisphere.
    @AppStorage(PeerFeed.nameKey) private var frontName = ""
    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(
        MKCoordinateRegion(center: .init(latitude: 43.6605, longitude: -79.4280),
                           span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))))
    /// Three resting heights, like Apple Maps: a peek with just search and one-tap chips,
    /// the half sheet, and pulled up with the bike's detail.
    enum Detent: String { case peek, half, full }
    // `-homeSheet peek|full` opens it there, for simulator screenshots.
    @State private var detent = Detent(rawValue: UserDefaults.standard.string(forKey: "homeSheet") ?? "") ?? .half
    private var expanded: Bool { detent == .full }

    static let peekHeight = 196.0
    static let restingHeight = 470.0
    static let expandedTop = 64.0

    var body: some View {
        GeometryReader { geo in
            let full = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            ZStack(alignment: .topLeading) {
                Map(position: $camera) { UserAnnotation() }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))

                if !expanded {
                    statusPill
                        .padding(.leading, 16).padding(.top, geo.safeAreaInsets.top + 8)
                        // Hidden: a 1.5 s hold starts the scripted ride, so the demo can be
                        // filmed with no Xcode tether and no rear phone.
                        .onLongPressGesture(minimumDuration: 1.5, perform: onDemo)
                }

                SheetFrame(detent: $detent, full: full) { sheetContent }
            }
            .ignoresSafeArea()
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: detent)
        }
        .environment(\.colorScheme, .light)
    }

    // MARK: - Status

    private enum Status { case ok, waiting, down, unknown }

    private var camera_: (Status, String) {
        switch model.link {
        case .connected: return (.ok, "Ready")
        case .searching: return (.waiting, "Looking…")
        case .lost: return (.down, "Offline")
        }
    }

    /// Only the rear phone talks to the grips; it says so in every frame. No link, or a
    /// rear build that predates the field, means we do not know.
    private var grips: (Status, String) {
        guard model.link == .connected, let g = model.frame?.grips else { return (.unknown, "–") }
        return g == "connected" ? (.ok, "Paired") : (.waiting, "Searching")
    }

    private var battery: String {
        guard model.link == .connected, let b = model.frame?.battery else { return "–" }
        return "\(Int((b * 100).rounded()))%"
    }

    private func colour(_ s: Status) -> Color {
        switch s {
        case .ok: return Light.green
        case .waiting: return Light.dim
        case .down: return Light.red
        case .unknown: return Light.faint
        }
    }

    private var statusPill: some View {
        HStack(spacing: 14) {
            pillItem("Camera", camera_.0)
            pillItem("Grips", grips.0)
        }
        .padding(.horizontal, 13).frame(height: 36)
        .background(.white.opacity(0.92), in: Capsule())
        .shadow(color: Light.shadow, radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }

    private func pillItem(_ label: String, _ s: Status) -> some View {
        HStack(spacing: 6) {
            Circle().fill(colour(s)).frame(width: 8, height: 8)
            Text(label).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Light.ink)
        }
    }

    // MARK: - Sheet

    private var sheetContent: some View {
        VStack(spacing: 0) {
            searchRow.padding(.horizontal, 16)

            if detent == .peek {
                chips.padding(.horizontal, 16).padding(.top, 14)
            }
            // Always laid out, below the fold when the sheet is low, so pulling it up
            // reveals the real places and recents as it moves, never an empty sheet.
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if expanded { bikeCard.transition(.opacity) }
                    places
                    recents
                    rides
                }
                .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 40)
            }
            .scrollDisabled(!expanded)
        }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Button { flow.pickingFor = nil; flow.picking = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold))
                    Text("Where to?")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(Light.dim)
                .padding(.horizontal, 16).frame(height: 50)
                .background(expanded ? .white : Light.field, in: RoundedRectangle(cornerRadius: 16))
            }
            Button { detent = expanded ? .half : .full } label: {
                Image(systemName: "bicycle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Light.blue, in: Circle())
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(colour(camera_.0 == .ok && grips.0 == .ok ? .ok : camera_.0))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Light.sheet, lineWidth: 2))
                            .offset(x: -1, y: 1)
                    }
            }
            .accessibilityLabel("Your bike: rear camera and grips")
        }
    }

    private func header(_ title: String, chevron: Bool = true) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
            if chevron { Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)) }
        }
        .foregroundStyle(Light.ink)
    }

    // MARK: - C: chips

    /// The peek's one row: Home, the latest recent, and a way to add, each one tap.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let home = flow.saved.home {
                    chip("house.fill", "Home", primary: true) { onPick(home.mapItem) }
                }
                if let last = flow.recents.items.first {
                    chip("clock", last.name) { onPick(last.mapItem) }
                }
                Button { flow.pickingFor = .extra; flow.picking = true } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Light.blue)
                        .frame(width: 44, height: 44)
                        .background(Light.field, in: Circle())
                }
                .accessibilityLabel("Add a place")
            }
        }
    }

    private func chip(_ symbol: String, _ title: String, primary: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(primary ? .white : Light.ink)
            .padding(.horizontal, 16).frame(height: 44)
            .background(primary ? Light.blue : Light.field, in: Capsule())
        }
    }

    // MARK: - B: bike

    private var bikeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Your bike", chevron: false)
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    bikeStat(camera_.1, "Rear camera", camera_.0)
                    bikeStat(grips.1, "Grips", grips.0)
                    bikeStat(battery, "Rear battery", nil)
                }
                .padding(.vertical, 14)
                Divider().overlay(Light.line)
                // What the rear phone's `-peer` argument has to match: iOS hands out a
                // generic "iPhone" without the device-name entitlement.
                HStack(spacing: 10) {
                    Text("This phone").foregroundStyle(Light.dim)
                    TextField(PeerLink.deviceName, text: $frontName)
                        .fontWeight(.semibold).foregroundStyle(Light.ink)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { model.restartFeed() }
                }
                .font(.system(size: 15, design: .rounded))
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .onLongPressGesture(minimumDuration: 1.5, perform: onDemo)
        }
    }

    private func bikeStat(_ value: String, _ label: String, _ s: Status?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let s { Circle().fill(colour(s)).frame(width: 8, height: 8) }
                Text(value).font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(s == .ok ? Light.green : Light.ink)
            }
            Text(label).font(.system(size: 13, design: .rounded)).foregroundStyle(Light.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Places

    private var places: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Places")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    placeCircle("house.fill", "Home", flow.saved.home, slot: .home, filled: true)
                    placeCircle("briefcase.fill", "Work", flow.saved.work, slot: .work)
                    ForEach(flow.saved.extra) { place in
                        placeCircle("mappin", place.name, place, slot: .extra)
                    }
                    placeCircle("plus", "Add", nil, slot: .extra, add: true)
                }
            }
        }
    }

    /// Set: one tap starts the route there. Unset: one tap picks it.
    private func placeCircle(_ symbol: String, _ title: String, _ place: RecentPlace?,
                             slot: SavedPlaces.Slot, filled: Bool = false, add: Bool = false) -> some View {
        Button {
            if let place { onPick(place.mapItem) } else { flow.pickingFor = slot; flow.picking = true }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: add ? 26 : 27, weight: add ? .semibold : .regular))
                    .foregroundStyle(filled && place != nil ? .white : Light.blue)
                    .frame(width: 64, height: 64)
                    .background(filled && place != nil ? Light.blue : Light.blueSoft, in: Circle())
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Light.ink).lineLimit(1)
                if !add {
                    Text(place == nil ? "Add" : place!.subtitle.isEmpty ? " " : place!.subtitle)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(place == nil ? Light.blue : Light.dim)
                        .lineLimit(1)
                        .padding(.top, -4)
                }
            }
            .frame(width: 76)
        }
    }

    // MARK: - Recents

    private var recents: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Recents")
            if flow.recents.items.isEmpty {
                Text("Nowhere yet. Search for somewhere to go, and it will wait here next time.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Light.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(flow.recents.items.prefix(expanded ? 6 : 2).enumerated()), id: \.element.id) { i, place in
                        if i > 0 { Divider().overlay(Light.line).padding(.leading, 48) }
                        Button { onPick(place.mapItem) } label: { row(place) }
                    }
                }
                .padding(.horizontal, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private func row(_ place: RecentPlace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Light.dim)
                .frame(width: 36, height: 36)
                .background(Light.field, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Light.ink)
                if !place.subtitle.isEmpty {
                    Text(place.subtitle)
                        .font(.system(size: 13.5, design: .rounded))
                        .foregroundStyle(Light.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - B: rides

    private var rides: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Your rides")
            Button(action: onRiskMap) {
                VStack(alignment: .leading, spacing: 2) {
                    ZStack {
                        Light.field
                        Image(systemName: "map.fill").font(.system(size: 30)).foregroundStyle(Light.blue.opacity(0.5))
                        Circle().fill(Light.red).frame(width: 8, height: 8).offset(x: -18, y: -6)
                        Circle().fill(Palette.amber).frame(width: 7, height: 7).offset(x: 26, y: 10)
                    }
                    .frame(height: 72)
                    Text("Close-pass map").font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Light.ink).padding(.horizontal, 12).padding(.top, 8)
                    Text("Where cars passed close").font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Light.dim).padding(.horizontal, 12).padding(.bottom, 10)
                }
                .frame(width: 180, alignment: .leading)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

/// The draggable sheet. Its own view, so a drag redraws only the sheet and never the map
/// behind it; always full height, so moving it is a pure slide with nothing re-laid out;
/// and the drag is measured on the screen, not on the handle that is moving with it.
private struct SheetFrame<Content: View>: View {
    @Binding var detent: PassiveHomeView.Detent
    let full: Double
    @ViewBuilder let content: () -> Content
    @State private var dragY = 0.0

    private func top(_ d: PassiveHomeView.Detent) -> Double {
        switch d {
        case .peek: full - PassiveHomeView.peekHeight
        case .half: full - PassiveHomeView.restingHeight
        case .full: PassiveHomeView.expandedTop
        }
    }

    var body: some View {
        let drag = DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { dragY = $0.translation.height }
            .onEnded { v in
                // Settle where the flick was heading, the nearest of the three heights.
                let aim = top(detent) + v.predictedEndTranslation.height
                let next = [PassiveHomeView.Detent.peek, .half, .full].min { abs(top($0) - aim) < abs(top($1) - aim) }!
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { detent = next; dragY = 0 }
            }
        VStack(spacing: 0) {
            Capsule().fill(Light.handle).frame(width: 40, height: 5)
                .padding(.top, 9).padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(drag)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: full - PassiveHomeView.expandedTop, alignment: .top)
        .background(Light.sheet)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
        .shadow(color: Light.shadow, radius: 14, y: -3)
        // Pulled up, the list scrolls and only the handle moves the sheet; lower down the
        // whole sheet can be dragged. High priority, so a drag that starts on the search bar
        // or a place moves the sheet and does not also tap what ends up under the finger.
        .highPriorityGesture(drag, including: detent == .full ? .subviews : .all)
        .offset(y: min(max(top(detent) + dragY, PassiveHomeView.expandedTop), top(.peek) + 40))
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: detent)
    }
}
