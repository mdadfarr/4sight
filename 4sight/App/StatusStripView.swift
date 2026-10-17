import SwiftUI

enum LinkState { case connected, searching, lost }

/// Thin strip shared by both roles: fps, thermal, speed km/h, link dot.
struct StatusStripView: View {
    let fps: Int
    let temp: String
    let speed: Double
    let link: LinkState

    var body: some View {
        HStack(spacing: 16) {
            Text("\(fps) fps")
            Text(temp)
            Text("\(Int((speed * 3.6).rounded())) km/h")
            Spacer()
            Circle().fill(dot).frame(width: 10, height: 10)
        }
        .font(.system(size: 13, design: .rounded).monospacedDigit())
        .foregroundStyle(Theme.textDim)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var dot: Color {
        switch link {
        case .connected: Theme.green
        case .searching: Theme.amber
        case .lost: Theme.red
        }
    }
}
