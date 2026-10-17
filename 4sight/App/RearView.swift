import SwiftUI

/// Rear-phone role. Perception pipeline lands in a later PR.
struct RearView: View {
    var body: some View {
        VStack {
            StatusStripView(fps: 0, temp: "nominal", speed: 0, link: .searching)
            Spacer()
            Text("Rear role: pipeline coming")
                .font(.system(.title2, design: .rounded))
                .foregroundStyle(Theme.textDim)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}
