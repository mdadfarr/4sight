import SwiftUI

/// The riding screen's one card at the top, in the home screen's language: floating,
/// inset from the edges, rounded like the home sheet, in its ink colour, with the map
/// running around it. Directions, the merge answer and the route warning are all this
/// card in a different colour, so it reads as one object changing state, not three
/// banners stacked on each other.
///
/// Measured in the 393 x 852 design space the HUD is laid out in.
enum GuidanceCard {
    static let inset = 10.0
    /// Just under the status bar and the Dynamic Island.
    static let top = 58.0
    static let height = 128.0
    static let radius = 28.0
    static var width: Double { Design.width - 2 * inset }
    static var bottom: Double { top + height }
}

/// The card's surface. Content is laid out by the caller.
struct GuidanceCardShell<Content: View>: View {
    let fill: Color
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 22)
            .frame(width: GuidanceCard.width, height: GuidanceCard.height, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: GuidanceCard.radius, style: .continuous))
            .shadow(color: Color(hex: 0x0C121A).opacity(0.22), radius: 18, y: 6)
    }
}

/// Icon, one bold line, one quieter line: the layout every alert state of the card shares.
struct GuidanceCardMessage: View {
    let icon: String
    let title: String
    var line: String? = nil
    let ink: Color

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .semibold))
                .frame(width: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
                if let line {
                    Text(line).font(.system(size: 18, weight: .semibold, design: .rounded)).opacity(0.85)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
    }
}

extension View {
    /// Places a guidance card at its spot in a full-screen design-space layer.
    func atGuidanceCard() -> some View {
        padding(.leading, GuidanceCard.inset).padding(.top, GuidanceCard.top)
            .frame(width: Design.width, height: Design.height, alignment: .topLeading)
    }
}
