import Protocol
import SwiftUI

/// The nav chrome: a black manoeuvre banner with a flat bottom edge so the map runs
/// under it, the speed badge, and the arrival card. Nothing else floats over the map;
/// destination and risk map live on the home and summary screens.
///
/// Laid out at fixed coordinates in the 393 x 852 design space and scaled once to the
/// screen.
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
                        .opacity(model.nav != nil ? 1 : 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bannerTitle).font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        Text(bannerLine).font(.system(size: 19, weight: .medium, design: .rounded))
                            .opacity(0.75)
                    }
                    .lineLimit(1).minimumScaleFactor(0.6)
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
    private var nearTurn: Bool {
        guard let nav = model.nav, headToRoute == nil else { return false }
        return nav.distanceToManoeuvre <= Self.turnNear
    }

    /// Metres back to the route when the rider is not on it: far from the route line, or
    /// off the street network altogether (inside a building, across a field). Apple starts
    /// a route at the phone's own position, indoors included, so the route line alone
    /// would call a rider on the second floor "on the route".
    private var headToRoute: Double? {
        guard let nav = model.nav else { return nil }
        if nav.isOffRoute { return nav.offRoute }
        guard let rider = model.route.riderCoordinate(at: Date()),
              let gap = StreetMap.at(rider)?.networkGap(rider) else { return nil }
        return gap.indoors || gap.metres > Self.offNetwork ? max(gap.metres, 5) : nil
    }
    static let offNetwork = 15.0

    private var bannerSymbol: String {
        guard model.nav != nil else { return "arrow.up" }
        if headToRoute != nil { return "location.north.line.fill" }
        guard nearTurn else { return "arrow.up" }
        return step(1)?.symbol ?? "flag.checkered"
    }
    private var bannerTitle: String {
        if let nav = model.nav {
            if headToRoute != nil { return "Head to the route" }
            let m = Self.metres(nav.distanceToManoeuvre)
            return nearTurn ? "In \(m)" : m
        }
        return ""
    }
    private var bannerLine: String {
        guard model.nav != nil else { return "No destination" }
        if let nav = model.nav, headToRoute != nil {
            // Indoors the distance is to a guessed fix, so only show it when the rider is outside and off the route.
            guard nav.isOffRoute else { return "Start on a road or path" }
            return Self.metres(nav.offRoute) + (nav.isWeakFix ? " away · weak GPS" : " away")
        }
        if model.nav?.isWeakFix == true { return "Weak GPS, distances are rough" }
        guard nearTurn else { return "Continue straight" }
        guard let next = step(1) else { return "Arrive at destination" }
        if next.symbol.contains("uturn") { return "Make a U-turn" }
        if next.symbol == "flag.checkered" { return "Arrive at \(next.street)" }
        return "Turn onto \(next.street)"
    }
    private var speedText: String {
        // This phone's own GPS first, then the rear phone's reading.
        let own = model.route.rider.flatMap { $0.speed >= 0 ? $0.speed : nil }
        guard let speed = own ?? model.frame?.speed else { return "–" }
        return "\(Int((speed * 3.6).rounded()))"
    }
    private var arrivalText: String {
        guard let nav = model.nav else { return "–" }
        return Self.clock(nav)
    }
    private var minutesText: String {
        guard let nav = model.nav else { return "–" }
        return "\(max(1, Int((nav.eta / 60).rounded(.up))))"
    }
    private var kmText: String {
        guard let nav = model.nav else { return "–" }
        return String(format: "%.1f", nav.remaining / 1000)
    }

    /// "120 m" under a kilometre, "2.3 km" above.
    /// Rounded like a car's nav: 5 m steps under 100 m, 10 m under 1 km, so GPS jitter
    /// does not make the number flicker.
    static func metres(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.1f km", m / 1000) }
        let step = m < 100 ? 5.0 : 10.0
        return "\(Int((m / step).rounded() * step)) m"
    }

    private static func clock(_ nav: NavState) -> String {
        let eta = nav.eta
        return Date(timeIntervalSinceNow: eta).formatted(date: .omitted, time: .shortened)
    }
}

/// Absolute placement in the design space. Inside a topLeading ZStack, setting a child's leading and
/// top guides puts its `anchor` point at (x, y).
private extension View {
    func at(_ x: Double, _ y: Double, anchor: UnitPoint = .center) -> some View {
        alignmentGuide(.leading) { d in anchor.x * d.width - x }
            .alignmentGuide(.top) { d in anchor.y * d.height - y }
    }
}
