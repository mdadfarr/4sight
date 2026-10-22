import Protocol
import SwiftUI

/// Whether the rear camera is awake, shown before the ride starts.
///
/// A maps app has no reason for this strip. 4sight does: the rider must not find out at
/// speed that the rear phone never woke up.
struct LinkStrip: View {
    @ObservedObject var model: FrontModel

    private var camera: (Color, String) {
        switch model.link {
        case .connected: (Light.green, "Ready")
        case .searching: (Light.dim, "Looking…")
        case .lost: (Light.red, "Offline")
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            item("Camera", camera)
        }
        .frame(height: 44)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func item(_ label: String, _ state: (Color, String)) -> some View {
        HStack(spacing: 7) {
            Circle().fill(state.0).frame(width: 8, height: 8)
            Text(label).foregroundStyle(Light.dim)
            Text(state.1).foregroundStyle(Light.ink).fontWeight(.semibold)
        }
        .font(.system(size: 14, design: .rounded))
        .frame(maxWidth: .infinity)
    }
}
