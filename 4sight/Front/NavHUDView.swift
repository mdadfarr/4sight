import Protocol
import SwiftUI

/// The nav chrome: a black manoeuvre banner with a flat bottom edge so the map runs
/// under it, the speed badge, and the arrival card. Nothing else floats over the map;
/// destination and risk map live on the home and summary screens.
///
/// Laid out at the mock's own coordinates in the 393 x 852 design space and scaled
/// once, so every position below is the number from the mock.
struct NavHUDView: View {
    @ObservedObject var model: FrontModel
    var onExit: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / Design.width
            content(height: geo.size.height / scale)
                .frame(width: Design.width, height: geo.size.height / scale, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
        }
    }

    /// One flat coordinate space: nested stacks would collapse these placements
    /// into each group's own bounds instead of the screen.
    private func content(height: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.at(0, 0, anchor: .topLeading)

            // Manoeuvre banner, flat along the bottom so the map runs under it.
            Rectangle().fill(Palette.banner)
                .frame(width: Design.width, height: Design.bannerH)
                .at(0, 0, anchor: .topLeading)
            // The mock paints a status bar because a canvas has none; the real one
            // already sits over this banner, so drawing a second would double it.

            Image(systemName: turnSymbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Palette.text).at(46, 104)
                .opacity(hasRoute ? 1 : 0)
            Text(distanceText).font(.system(size: 36, weight: .bold, design: .rounded))
                .fixedSize().foregroundStyle(Palette.text).at(84, 116, anchor: .bottomLeading)
            Text(streetText).font(.system(size: 21, weight: .medium, design: .rounded))
                .fixedSize().foregroundStyle(Palette.text).at(84, 144, anchor: .bottomLeading)

            Rectangle().fill(Palette.hair)
                .frame(width: Design.width - 40, height: 1).at(20, 160, anchor: .topLeading)
            Text("Then").font(.system(size: 15, design: .rounded))
                .fixedSize().foregroundStyle(Palette.textDim).at(22, 182, anchor: .bottomLeading)
            Image(systemName: thenSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.text).at(72, 176)
                .opacity(hasRoute ? 1 : 0)
            Text(thenText).font(.system(size: 15, weight: .medium, design: .rounded))
                .fixedSize().foregroundStyle(Palette.text).at(90, 182, anchor: .bottomLeading)

            speedBadge.at(16, Design.bannerH + 14, anchor: .topLeading)

            arrivalBar.at(0, height - Self.cardH, anchor: .topLeading)
        }
        .frame(width: Design.width, height: height, alignment: .topLeading)
    }

    private var speedBadge: some View {
        VStack(spacing: 0) {
            Text(speedText).font(.system(size: 21, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.barInk)
            Text("km/h").font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.barDim)
        }
        .frame(width: 54, height: 50)
        .background(Palette.bar, in: RoundedRectangle(cornerRadius: 12))
        // Rear-phone link: green while frames arrive.
        .overlay(alignment: .topTrailing) {
            Circle().fill(model.link == .connected ? Palette.green : Palette.exit)
                .frame(width: 8, height: 8).offset(x: -6, y: 6)
        }
        .shadow(color: Color(hex: 0x0C121A).opacity(0.22), radius: 4, y: 2)
    }

    static let cardH = 112.0

    /// Google Maps' bottom card, pared down: time left is the one number that matters
    /// on a bike, so it leads in green; distance and arrival clock sit under it.
    private var arrivalBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(minutesText)
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    Text("min").font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Palette.eta)
                Text("\(kmText) km  ·  \(arrivalText)")
                    .font(.system(size: 15, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(Palette.barDim)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            // Big enough for a gloved thumb on a moving bike, quiet enough not to
            // compete with a warning.
            Button(action: onExit) {
                Text("Exit")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 48)
                    .background(Palette.exit, in: Capsule())
            }
        }
        .padding(.horizontal, 24).padding(.top, 18)
        .frame(width: Design.width, height: Self.cardH, alignment: .top)
        .background(Palette.bar)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .shadow(color: Color(hex: 0x0C121A).opacity(0.12), radius: 12, y: -2)
        .overlay(alignment: .top) {
            Capsule().fill(Palette.hairDark).frame(width: 36, height: 4).padding(.top, 7)
        }
    }

    // MARK: - Copy
    // Real routing when a destination is set; otherwise the scripted ride, so the
    // demo and the screenshots read the same as the mock.

    private var t: Double { model.now() }

    /// The scripted ride counts down to its own turn. `now()` is seconds since the
    /// reference date on a live feed, so this is only meaningful on the script's clock.
    private var scriptedDistance: String {
        let travelled = World.speed * t.truncatingRemainder(dividingBy: SyntheticFeed.loop)
        return "\(max(5, Int((World.turnStreet.ahead - travelled) / 5).magnitude * 5)) m"
    }

    private var distanceText: String {
        if let nav = model.nav { return Self.metres(nav.distanceToManoeuvre) }
        return model.scripted ? scriptedDistance : ""
    }
    /// MKRoute steps start with their manoeuvre, so the turn at the end of the current
    /// step is the next step's: "↱ 228 m, Ellesmere Road", like Google Maps.
    private func step(_ ahead: Int) -> NavStep? {
        guard let nav = model.nav, nav.currentIndex + ahead < nav.steps.count else { return nil }
        return nav.steps[nav.currentIndex + ahead]
    }
    private var turnSymbol: String {
        if model.nav != nil { return step(1)?.symbol ?? "flag.checkered" }
        return "arrow.turn.up.left"
    }
    private var thenSymbol: String {
        if model.nav != nil { return step(2)?.symbol ?? "flag.checkered" }
        return "arrow.turn.up.right"
    }
    private var streetText: String {
        if let nav = model.nav { return step(1)?.street ?? nav.current.street }
        return model.scripted ? World.turnStreet.name : "No destination"
    }
    private var thenText: String {
        guard model.nav != nil else {
            return model.scripted ? "900 m · Bloor St W" : "Set one from the route button"
        }
        guard let then = step(2) else { return step(1) == nil ? "Arrive" : "Then arrive" }
        return "\(Self.metres(step(1)?.distance ?? 0)) · \(then.street)"
    }
    /// A route or the script means there is a speed to show; a live feed with no frame
    /// yet does not, and a standing-still readout of 13 km/h would be a lie.
    private var hasRoute: Bool { model.nav != nil || model.scripted }

    private var speedText: String {
        guard let speed = model.frame?.speed ?? (hasRoute ? World.speed : nil) else { return "–" }
        return "\(Int((speed * 3.6).rounded()))"
    }
    private var arrivalText: String {
        guard let nav = model.nav else { return model.scripted ? "12:41" : "–" }
        return Self.clock(nav)
    }
    private var minutesText: String {
        guard let nav = model.nav, let eta = nav.eta(speed: model.frame?.speed ?? World.speed)
        else { return model.nav == nil && !model.scripted ? "–" : "18" }
        return "\(Int((eta / 60).rounded(.up)))"
    }
    private var kmText: String {
        guard let nav = model.nav else { return model.scripted ? "4.2" : "–" }
        return String(format: "%.1f", nav.remaining / 1000)
    }

    /// "120 m" under a kilometre, "2.3 km" above.
    static func metres(_ m: Double) -> String {
        m < 1000 ? "\(Int(m.rounded())) m" : String(format: "%.1f km", m / 1000)
    }

    private static func clock(_ nav: NavState) -> String {
        let eta = nav.eta(speed: World.speed) ?? 0
        return Date(timeIntervalSinceNow: eta).formatted(date: .omitted, time: .shortened)
    }
}

/// Absolute placement in the design space, so each call below reads like the
/// mock's own draw call. Inside a topLeading ZStack, setting a child's leading and
/// top guides puts its `anchor` point at (x, y).
private extension View {
    func at(_ x: Double, _ y: Double, anchor: UnitPoint = .center) -> some View {
        alignmentGuide(.leading) { d in anchor.x * d.width - x }
            .alignmentGuide(.top) { d in anchor.y * d.height - y }
    }
}
