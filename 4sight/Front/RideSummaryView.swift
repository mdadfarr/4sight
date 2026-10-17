import SwiftUI

/// The ride, closed off. Two of these four figures are the reason 4sight exists, so
/// they are the ones that carry colour; the counts are what this phone actually saw,
/// not an estimate.
struct RideSummaryView: View {
    let summary: RideSummary
    let onRiskMap: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("You're here")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text("\(summary.destination) · \(summary.minutes) min")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .padding(.top, 6)

            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    tile("Distance", summary.distanceText, Theme.text)
                    tile("Ride time", "\(summary.minutes) min", Theme.text)
                }
                GridRow {
                    tile("Close passes", "\(summary.closePasses)", Theme.amber)
                    tile("Imminent", "\(summary.imminent)", Theme.red)
                }
            }
            .padding(.top, 30)

            Spacer(minLength: 20)

            Button(action: onRiskMap) {
                Text("See them on the map")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.ground, in: RoundedRectangle(cornerRadius: 13))
            }
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Palette.routeCore, in: RoundedRectangle(cornerRadius: 13))
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 26)
        .padding(.top, 86)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private func tile(_ key: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key.uppercased())
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .kerning(0.7)
                .foregroundStyle(Theme.silhouette)
            Text(value)
                .font(.system(size: 27, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 14))
    }
}
