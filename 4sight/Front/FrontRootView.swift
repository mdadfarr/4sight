import SwiftUI

struct FrontRootView: View {
    @StateObject private var model = FrontModel()
    @State private var router = NavRouter()
    @State private var pickingDestination = false
    private let args = LaunchArgs()

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                NavHUDView(model: model) { pickingDestination = true }
                    .frame(height: geo.size.height / 3)
                SurroundView(model: model)
            }
        }
        .background(Theme.bg)
        .overlay { EdgeGlowView(model: model) }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $pickingDestination) {
            DestinationPickerView { item in Task { try? await router.route(to: item) } }
        }
        .onAppear {
            // shortcut: PeerFeed lands in front/peer-feed; until then everything is synthetic.
            model.freeze = args.freeze
            if args.mockRoute {
                model.nav = .mock
            } else {
                router.onUpdate = { model.nav = $0 }
                router.requestAuthorization()
                pickingDestination = true
            }
            model.start(feed: SyntheticFeed(scenario: args.scenario, freeze: args.freeze))
        }
    }
}
