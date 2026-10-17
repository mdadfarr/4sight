import SwiftUI

/// The front screen: the follow view with the map and traffic, the nav chrome over
/// it, and the edge warning painted last on top of both.
struct FrontRootView: View {
    @StateObject private var model = FrontModel()
    @State private var router = NavRouter()
    @State private var pickingDestination = false
    private let args = LaunchArgs()

    var body: some View {
        ZStack {
            SurroundView(model: model)
            NavHUDView(model: model) { pickingDestination = true }
            AlertOverlay(model: model)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .sheet(isPresented: $pickingDestination) {
            DestinationPickerView { item in Task { try? await router.route(to: item) } }
        }
        .onAppear(perform: begin)
    }

    private func begin() {
        model.freeze = args.freeze
        if args.mockRoute {
            model.nav = .mock
        } else if !args.synthetic {
            // The picker is opened from the route button, never over the display.
            router.onUpdate = { model.nav = $0 }
            router.requestAuthorization()
        }
        model.start(feed: args.synthetic
                    ? SyntheticFeed(freeze: args.freeze, demo: args.demo)
                    : PeerFeed())
    }
}
