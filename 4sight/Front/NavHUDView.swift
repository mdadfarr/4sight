import SwiftUI
import Protocol

/// Top band: next manoeuvre, ETA line, status strip.
struct NavHUDView: View {
    @ObservedObject var model: FrontModel

    var body: some View {
        VStack(spacing: 0) {
            if let nav = model.nav {
                HStack(spacing: 20) {
                    Image(systemName: nav.current.symbol)
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 72)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.metres(nav.distanceToManoeuvre))
                            .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.text)
                        Text(nav.current.street)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Text(etaLine(nav))
                    .font(.system(size: 17, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textDim)
                    .padding(.top, 8)
                StatusStripView(fps: model.frame?.fps ?? 0,
                                temp: model.frame?.temp.rawValue ?? "–",
                                speed: model.frame?.speed ?? 0,
                                link: model.link)
                    .padding(.top, 6)
            } else {
                Text("No route")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .frame(maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func etaLine(_ nav: NavState) -> String {
        let speed = model.frame?.speed ?? 0
        let eta = nav.eta(speed: speed).map { "\(Int(($0 / 60).rounded(.up))) min" } ?? "– min"
        return "\(eta) · \(Self.metres(nav.remaining))"
    }

    /// "120 m" under 1 km, "2.3 km" above.
    static func metres(_ m: Double) -> String {
        m < 1000 ? "\(Int(m.rounded())) m" : String(format: "%.1f km", m / 1000)
    }
}
