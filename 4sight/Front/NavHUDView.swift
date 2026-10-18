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

            // Directions: the floating guidance card, in the home screen's ink. Read at a
            // glance from a moving bike: one big arrow for what to do now, one big
            // number, one short line. The arrow only turns near the turn.
            GuidanceCardShell(fill: Light.ink) {
                HStack(spacing: 16) {
                    Image(systemName: bannerSymbol)
                        .font(.system(size: 50, weight: .semibold))
                        .frame(width: 58)
                        .opacity(hasRoute ? 1 : 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bannerTitle).font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        Text(bannerLine).font(.system(size: 19, weight: .medium, design: .rounded))
                            .opacity(0.75)
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
            }
            .at(GuidanceCard.inset, GuidanceCard.top, anchor: .topLeading)

            // A planned lane move: a small pill tucked under the card, in its ink, because
            // amber and red already mean warnings on this screen.
            if let cue = laneCue {
                HStack(spacing: 7) {
                    Image(systemName: cue.symbol).font(.system(size: 13, weight: .bold))
                    Text("\(cue.text) · \(Self.metres(max(cue.metres, 5)))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Light.ink.opacity(0.92), in: Capsule())
                .shadow(color: Light.shadow, radius: 8, y: 2)
                .fixedSize()
                .at(GuidanceCard.inset + 8, GuidanceCard.bottom + 8, anchor: .topLeading)
            }

            // Speed sits low on the left above the arrival card, as in Apple Maps, so the
            // top of the screen is only the guidance card.
            speedBadge.at(GuidanceCard.inset + 6, height - Self.cardH - Self.cardBottom - 14, anchor: .bottomLeading)

            arrivalBar.at(GuidanceCard.inset, height - Self.cardH - Self.cardBottom, anchor: .topLeading)
        }
        .frame(width: Design.width, height: height, alignment: .topLeading)
    }

    private var speedBadge: some View {
        VStack(spacing: 0) {
            Text(speedText).font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Light.ink)
            Text("km/h").font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Light.dim)
        }
        .frame(width: 60, height: 60)
        .background(.white, in: Circle())
        // Rear-phone link: green while frames arrive.
        .overlay(alignment: .topTrailing) {
            Circle().fill(model.link == .connected ? Light.green : Light.red)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .offset(x: -1, y: 1)
        }
        .shadow(color: Light.shadow, radius: 10, y: 3)
    }

    /// The arrival card floats like the guidance card, above the home indicator.
    static let cardH = 86.0
    static let cardBottom = 30.0

    private var arrivalBar: some View {
        currentCard
        .padding(.horizontal, 20)
        .frame(width: GuidanceCard.width, height: Self.cardH)
        .background(.white, in: RoundedRectangle(cornerRadius: GuidanceCard.radius, style: .continuous))
        .shadow(color: Color(hex: 0x0C121A).opacity(0.16), radius: 18, y: 4)
    }

    /// Google Maps' bottom card, pared down: time left is the one number that matters
    /// on a bike, so it leads in green; distance and arrival clock sit under it.
    private var currentCard: some View {
        HStack(alignment: .center, spacing: 12) {
            etaStack
            Spacer(minLength: 0)
            exitButton(width: 84)
        }
    }

    private var etaStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(minutesText)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                Text("min").font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Palette.eta)
            Text("\(kmText) km  ·  \(arrivalText)")
                .font(.system(size: 15, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Light.dim)
        }
        .lineLimit(1)
    }

    /// Big enough for a gloved thumb on a moving bike, quiet enough not to compete
    /// with a warning.
    private func exitButton(width: Double) -> some View {
        Button(action: onExit) {
            Text("Exit")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: width, height: 50)
                .background(Light.red, in: Capsule())
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

    /// Within this of the turn the banner switches from "continue" to the turn itself:
    /// about 12 s of warning at 15 km/h.
    static let turnNear = 50.0

    /// MKRoute steps start with their manoeuvre, so the turn at the end of the current
    /// step is the next step's.
    private func step(_ ahead: Int) -> NavStep? {
        guard let nav = model.nav, nav.currentIndex + ahead < nav.steps.count else { return nil }
        return nav.steps[nav.currentIndex + ahead]
    }
    private var laneCue: (text: String, symbol: String, metres: Double)? {
        guard let rider = model.route.riderCoordinate(at: Date()) else { return nil }
        return model.lanePlan?.cue(at: rider)
    }
    private var nearTurn: Bool { (model.nav?.distanceToManoeuvre ?? 0) <= Self.turnNear }

    private var bannerSymbol: String {
        guard model.nav != nil else { return "arrow.turn.up.left" }      // the script's turn
        guard nearTurn else { return "arrow.up" }
        return step(1)?.symbol ?? "flag.checkered"
    }
    private var bannerTitle: String {
        if let nav = model.nav {
            let m = Self.metres(nav.distanceToManoeuvre)
            return nearTurn ? "In \(m)" : m
        }
        return model.scripted ? "In \(scriptedDistance)" : ""
    }
    private var bannerLine: String {
        guard model.nav != nil else {
            return model.scripted ? "Turn onto \(World.turnStreet.name)" : "No destination"
        }
        guard nearTurn else { return "Continue straight" }
        guard let next = step(1) else { return "Arrive at destination" }
        if next.symbol.contains("uturn") { return "Make a U-turn" }
        if next.symbol == "flag.checkered" { return "Arrive at \(next.street)" }
        return "Turn onto \(next.street)"
    }
    /// A route or the script means there is a speed to show; a live feed with no frame
    /// yet does not, and a standing-still readout of 13 km/h would be a lie.
    private var hasRoute: Bool { model.nav != nil || model.scripted }

    private var speedText: String {
        // This phone's own GPS first; the rear phone's reading, then the script's, after.
        let own = model.route.rider.flatMap { $0.speed >= 0 ? $0.speed : nil }
        guard let speed = own ?? model.frame?.speed ?? (hasRoute ? World.speed : nil) else { return "–" }
        return "\(Int((speed * 3.6).rounded()))"
    }
    private var arrivalText: String {
        guard let nav = model.nav else { return model.scripted ? "12:41" : "–" }
        return Self.clock(nav)
    }
    private var minutesText: String {
        guard let nav = model.nav else { return model.scripted ? "18" : "–" }
        return "\(max(1, Int((nav.eta / 60).rounded(.up))))"
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
        let eta = nav.eta
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
