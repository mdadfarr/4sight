import SwiftUI

/// The front screen: the follow view with the map and traffic, the nav chrome over
/// it, and the edge warning painted last on top of both.
struct FrontRootView: View {
    @StateObject private var model = FrontModel()
    @State private var router = NavRouter()
    @State private var pickingDestination = false
    @State private var showingRiskMap = false
    private let args = LaunchArgs()

    var body: some View {
        ZStack {
            SurroundView(model: model)
            NavHUDView(model: model,
                       onPickDestination: { pickingDestination = true },
                       onRiskMap: { showingRiskMap = true })
            AlertOverlay(model: model)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .sheet(isPresented: $pickingDestination) {
            DestinationPickerView { item in Task { try? await router.route(to: item) } }
        }
        .sheet(isPresented: $showingRiskMap) {
            RiskMapView(demo: args.demoEvents)
        }
        .onAppear(perform: begin)
    }

    private func begin() {
        // Opening it on launch is how the screen gets demoed and screenshotted; the
        // close button drops back to the follow view.
        showingRiskMap = args.demoEvents
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
