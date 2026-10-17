import Protocol
import SwiftUI

/// The nav chrome from `docs/mock/front.html`: a black manoeuvre banner with a flat
/// bottom edge so the map runs under it rather than under a floating card, the speed
/// badge and two controls over the map, and a white arrival bar.
///
/// Laid out at the mock's own coordinates in the 393 x 852 design space and scaled
/// once, so every position below is the number from the mock.
struct NavHUDView: View {
    @ObservedObject var model: FrontModel
    var onPickDestination: () -> Void = {}
    var onRiskMap: () -> Void = {}

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

            Image(systemName: "arrow.turn.up.left")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Palette.text).at(46, 104)
                .opacity(hasRoute ? 1 : 0)
            Text(distanceText).font(.system(size: 36, weight: .bold, design: .rounded))
                .fixedSize().foregroundStyle(Palette.text).at(84, 116, anchor: .bottomLeading)
            Text(streetText).font(.system(size: 21, weight: .medium, design: .rounded))
                .fixedSize().foregroundStyle(Palette.text).at(84, 144, anchor: .bottomLeading)
            bikeLanePill.at(Design.width - 20, 100, anchor: .trailing)

            Rectangle().fill(Palette.hair)
                .frame(width: Design.width - 40, height: 1).at(20, 160, anchor: .topLeading)
            Text("Then").font(.system(size: 15, design: .rounded))
                .fixedSize().foregroundStyle(Palette.textDim).at(22, 182, anchor: .bottomLeading)
            Image(systemName: "arrow.turn.up.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.text).at(72, 176)
                .opacity(hasRoute ? 1 : 0)
            Text(thenText).font(.system(size: 15, weight: .medium, design: .rounded))
                .fixedSize().foregroundStyle(Palette.text).at(90, 182, anchor: .bottomLeading)

            // Over the map: speed, and the two controls a rider reaches for.
            speedBadge.at(16, Design.bannerH + 14, anchor: .topLeading)
            circleButton("point.topleft.down.to.point.bottomright.curvepath", action: onPickDestination)
                .at(Design.width - 38, Design.bannerH + 30)
            circleButton("speaker.wave.2.fill", action: {})
                .at(Design.width - 38, Design.bannerH + 84)
            // Not in the mock: the risk map needs a way in, and this column is where
            // the mock already puts the map's own controls.
            circleButton("map.fill", action: onRiskMap)
                .at(Design.width - 38, Design.bannerH + 138)
            Circle().fill(model.link == .connected ? Palette.green : Palette.exit)
                .frame(width: 9, height: 9).at(Design.width - 22, Design.bannerH + 14)

            arrivalBar.at(0, height - 96, anchor: .topLeading)
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
        .shadow(color: Color(hex: 0x0C121A).opacity(0.22), radius: 4, y: 2)
    }

    private var bikeLanePill: some View {
        Text("Bike Lane")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .fixedSize().foregroundStyle(Palette.text)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(hex: 0x1F8B4C), in: Capsule())
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.puck)
                .frame(width: 44, height: 44)
                .background(Palette.bar, in: Circle())
        }
        .shadow(color: Color(hex: 0x0C121A).opacity(0.22), radius: 4, y: 2)
    }

    private var arrivalBar: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(arrivalText, "arrival").frame(width: 140, alignment: .leading)
            stat(minutesText, "min").frame(width: 64, alignment: .leading)
            stat(kmText, "km").frame(width: 90, alignment: .leading)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.barDim)
                .frame(width: 38, height: 38)
                .background(Color(hex: 0xE7E9ED), in: Circle())
                .padding(.top, 8)
        }
        .padding(.horizontal, 24).padding(.top, 26)
        .frame(width: Design.width, height: 120, alignment: .topLeading)
        .background(Palette.bar)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(Palette.barInk)
            Text(label).font(.system(size: 13, weight: .medium, design: .rounded))
                .fixedSize().foregroundStyle(Palette.barDim)
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
    private var streetText: String {
        if let nav = model.nav { return nav.current.street }
        return model.scripted ? World.turnStreet.name : "No destination"
    }
    private var thenText: String {
        guard let nav = model.nav, nav.currentIndex + 1 < nav.steps.count else {
            return model.nav == nil && !model.scripted
                ? "Set one from the route button" : "900 m · Bloor St W"
        }
        let next = nav.steps[nav.currentIndex + 1]
        return "\(Self.metres(next.distance)) · \(next.street)"
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
