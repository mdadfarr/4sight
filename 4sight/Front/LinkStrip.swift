import Protocol
import SwiftUI

/// Whether the rest of the bike is awake, shown before the ride starts: the rear camera
/// (the link to the rear phone) and the handlebar grips (which only the rear phone talks
/// to, so it reports them in every frame).
///
/// A maps app has no reason for this strip. 4sight does: the rider must not find out at
/// speed that the rear phone never woke up or the grips never paired.
struct LinkStrip: View {
    @ObservedObject var model: FrontModel

    private var camera: (Color, String) {
        switch model.link {
        case .connected: (Light.green, "Ready")
        case .searching: (Light.dim, "Looking…")
        case .lost: (Light.red, "Offline")
        }
    }

    /// No link, or a rear build older than the field: unknown, not "not paired".
    private var grips: (Color, String) {
        guard model.link == .connected, let g = model.frame?.grips else { return (Light.faint, "Unknown") }
        return g == "connected" ? (Light.green, "Paired") : (Light.red, "Not paired")
    }

    var body: some View {
        HStack(spacing: 0) {
            item("Camera", camera)
            Rectangle().fill(Light.line).frame(width: 1, height: 22)
            item("Grips", grips)
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
