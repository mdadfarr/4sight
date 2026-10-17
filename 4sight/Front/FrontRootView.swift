import SwiftUI

struct FrontRootView: View {
    @StateObject private var model = FrontModel()
    private let args = LaunchArgs()

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                NavHUDView(model: model)
                    .frame(height: geo.size.height / 3)
                SurroundView(model: model)
            }
        }
        .background(Theme.bg)
        .overlay { EdgeGlowView(model: model) }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .onAppear {
            // shortcut: PeerFeed lands in front/peer-feed; until then everything is synthetic.
            model.freeze = args.freeze
            if args.mockRoute { model.nav = .mock }
            model.start(feed: SyntheticFeed(scenario: args.scenario, freeze: args.freeze))
        }
    }
}
