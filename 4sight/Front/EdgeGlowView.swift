import SwiftUI
import Protocol

/// Full-height red glow on the screen edge facing any level-3 track, pulsing at 1 Hz.
struct EdgeGlowView: View {
    @ObservedObject var model: FrontModel
    static let width: CGFloat = 120

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / 20)) { timeline in
            let tracks = model.frame?.tracks ?? []
            let left = tracks.contains { $0.level == 3 && $0.x < 0 }
            let right = tracks.contains { $0.level == 3 && $0.x >= 0 }
            let alpha = 0.7 * (0.6 + 0.4 * TrackGlyph.pulse(model.now(timeline.date)))
            HStack {
                if left {
                    LinearGradient(colors: [Theme.red.opacity(alpha), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.width)
                }
                Spacer()
                if right {
                    LinearGradient(colors: [.clear, Theme.red.opacity(alpha)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.width)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
