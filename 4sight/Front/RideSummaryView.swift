import SwiftUI

/// The ride, closed off, in the riding screen's language: the same floating ink card at
/// the top (now saying you're here), one white card of figures under it, and the home
/// sheet's buttons at the bottom. The two counts are why 4sight exists, so they are the
/// big, coloured ones; distance and time sit small beside them. Counts are what this
/// phone saw, not an estimate.
struct RideSummaryView: View {
    let summary: RideSummary
    let onRiskMap: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            GuidanceCardShell(fill: Light.ink) {
                GuidanceCardMessage(icon: "flag.checkered", title: "You're here",
                                    line: summary.destination, ink: .white)
            }
            figures
            Spacer(minLength: 12)
            Button(action: onRiskMap) {
                Label("See them on the map", systemImage: "map")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Light.ink)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.white, in: Capsule())
                    .shadow(color: Light.ink.opacity(0.08), radius: 10, y: 3)
            }
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Palette.routeCore, in: Capsule())
            }
        }
        .padding(.horizontal, GuidanceCard.inset)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.liveGround.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private var figures: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 12) {
                count("Close passes", summary.closePasses, Light.amber)
                count("Imminent", summary.imminent, Light.red)
            }
            Divider().overlay(Light.line)
            HStack(spacing: 12) {
                small("Distance", summary.distanceText)
                small("Ride time", "\(summary.minutes) min")
            }
            Text(summary.closePasses == 0
                 ? "No close passes this ride."
                 : "Each one is now an anonymous point on Toronto's safety map.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Light.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: GuidanceCard.radius, style: .continuous))
        .shadow(color: Light.ink.opacity(0.10), radius: 18, y: 6)
    }

    private func count(_ key: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(value == 0 ? Light.faint : tint)
            Text(key)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Light.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key.uppercased())
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .kerning(0.7)
                .foregroundStyle(Light.faint)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Light.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    RideSummaryView(summary: RideSummary(destination: "Toronto Pan Am Sports Centre", seconds: 840,
                                         metres: 3200, closePasses: 2, imminent: 1),
                    onRiskMap: {}, onDone: {})
}
