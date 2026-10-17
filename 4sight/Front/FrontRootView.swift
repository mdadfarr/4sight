import SwiftUI

struct FrontRootView: View {
    @StateObject private var model = FrontModel()
    private let args = LaunchArgs()

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Color.clear.frame(height: geo.size.height / 3) // nav HUD, later PR
                SurroundView(model: model)
            }
        }
        .background(Theme.bg)
        .overlay { EdgeGlowView(model: model) }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            // shortcut: PeerFeed lands in front/peer-feed; until then everything is synthetic.
            model.freeze = args.freeze
            model.start(feed: SyntheticFeed(scenario: args.scenario, freeze: args.freeze))
        }
    }
}
