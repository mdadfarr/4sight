import MapKit
import SwiftUI

/// The first screen on every launch: which phone is this? One tap, the last choice marked,
/// so the set-up is "open the app on both phones, pick front and rear, mount them".
/// Asking each time (rather than remembering) means swapping phones never needs a hidden
/// gesture. `-role front|rear` skips it, for the simulator scripts.
struct RolePickerView: View {
    @State private var role = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["role"] as? String ?? ""
    @AppStorage("lastRole") private var lastRole = ""
    /// The opening moment: the logo alone in the middle, pulsing once, then it rises into
    /// its place on the role screen while the map and the choices fade in.
    @State private var splash = true
    @State private var pulse = false
    /// Where the logo sits on the role screen, to start it from the middle of the screen.
    @State private var logoMidY: CGFloat = 0

    var body: some View {
        switch role {
        case "rear": RearView().preferredColorScheme(.dark)
        case "front": FrontRootView()
        default: picker
        }
    }

    /// The app icon itself, so the splash and the home screen show the same mark.
    private var logo: some View {
        Image("Logo")
            .resizable()
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Light.blue.opacity(0.3), radius: 12, y: 6)
    }

    /// One logo throughout: it starts in the middle of the screen with everything else
    /// hidden, breathes once while the app gets ready, then glides up into its place as
    /// the map and the choices fade in.
    private var picker: some View {
        GeometryReader { geo in
            choices(lift: splash ? geo.frame(in: .global).midY - logoMidY : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) { splash = false }
            }
        }
    }

    private func choices(lift: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            // The logo's resting place, measured unmoved; the logo itself is drawn over it
            // and slid from the middle of the screen.
            Color.clear
                .frame(width: 88, height: 88)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midY } action: { logoMidY = $0; PassiveHomeView.pinY = $0 }
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(Light.blue.opacity(pulse ? 0 : 0.35), lineWidth: 2)
                            .frame(width: pulse ? 150 : 96, height: pulse ? 150 : 96)
                            .opacity(splash ? 1 : 0)
                        logo
                    }
                    .offset(y: lift)
                    .opacity(logoMidY == 0 ? 0 : 1)          // not until its place is known
                }
                .zIndex(1)
            Group {
                Text("4sight")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Light.ink)
                    .padding(.top, 18)
                Text("See what\u{2019}s coming from behind.")
                    .font(.system(size: 17, design: .rounded))
                    .foregroundStyle(Light.dim)
                    .padding(.top, 4)

                Spacer(minLength: 20)
                Text("Where is this phone going?")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Light.ink)
                    .padding(.bottom, 16)
                HStack(spacing: 12) {
                    choice("front", title: "Handlebar", symbol: "bicycle")
                    choice("rear", title: "Rear rack", symbol: "camera.fill")
                }
            }
            .opacity(splash ? 0 : 1)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { backdrop }
        .preferredColorScheme(.light)
    }

    /// The rider's own streets behind the logo, fading into the sheet colour where the
    /// choices are: every other screen in the app sits on the map, so this one does too.
    private var backdrop: some View {
        ZStack {
            Light.sheet
            // Not until the splash is done: the map is slow to start, and the first frame
            // has to be light enough for the logo to show before it.
            if !splash {
                GeometryReader { geo in
                    Map(initialPosition: .userLocation(fallback: .region(MKCoordinateRegion(
                        center: .init(latitude: 43.7845, longitude: -79.1873),
                        span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))), interactionModes: []) {}
                        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                        // Twice the screen tall and centred on the logo's resting place, so the
                        // rider's own spot sits under the logo, not in the middle of the screen.
                        .frame(height: geo.size.height * 2)
                        .position(x: geo.size.width / 2, y: logoMidY)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            Light.sheet.opacity(splash ? 1 : 0)
            LinearGradient(stops: [.init(color: Light.sheet.opacity(0.35), location: 0),
                                   .init(color: Light.sheet.opacity(0.75), location: 0.3),
                                   .init(color: Light.sheet, location: 0.55)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    /// One role, in the Places circles' style from the home screen.
    private func choice(_ value: String, title: String, symbol: String) -> some View {
        let last = lastRole == value
        return Button {
            lastRole = value
            role = value
        } label: {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(last ? .white : Light.blue)
                    .frame(width: 72, height: 72)
                    .background(last ? Light.blue : Light.blueSoft, in: Circle())
                Text(title).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Light.ink)
                Text(last ? "Last used" : " ")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Light.blue)
            }
            .padding(.top, 22).padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(last ? Light.blue : .clear, lineWidth: 2))
            .shadow(color: Light.shadow, radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
