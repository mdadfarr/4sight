import Protocol
import SwiftUI
import ThreatEngine

/// Where the route meets traffic from behind (see ThreatEngine/TurnConflict.swift): before a
/// left turn, a vehicle coming up on the left; at a junction the rider goes straight
/// through, a car overtaking that may turn right across them (the right hook); before a
/// right turn, a cyclist squeezing past on the right. It takes over the manoeuvre banner in
/// amber: the guidance card turns amber. Navigation knows what is ahead and the rear camera knows who is coming.
///
/// Held 1.5 s after the vehicle clears, so a track flickering out for a frame cannot make
/// the banner blink. The merge answer, drawn above it, still wins while it shows.
struct TurnWarningBanner: View {
    @ObservedObject var model: FrontModel
    @State private var hold = Hold()

    static let holdSeconds = 1.5

    /// Not observed: the timeline below redraws often enough to read it.
    private final class Hold {
        var conflict: RouteConflict?
        var until = Date.distantPast
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
            GeometryReader { geo in
                let scale = geo.size.width / Design.width
                if let shown = warning(at: timeline.date) {
                    panel(shown)
                        .atGuidanceCard()
                        .scaleEffect(scale, anchor: .topLeading)
                        .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Re-evaluates the conflict for this moment and returns what to show, if anything.
    private func warning(at now: Date) -> RouteConflict? {
        if model.link == .connected, let frame = model.frame, let ahead = manoeuvre(at: now),
           let hit = routeConflict(ahead, tracks: frame.tracks) {
            hold.conflict = hit
            hold.until = now.addingTimeInterval(Self.holdSeconds)
        }
        return now < hold.until ? hold.conflict : nil
    }

    /// What is ahead: the next turn when it is close, else the next junction straight through.
    private func manoeuvre(at now: Date) -> RouteManoeuvre? {
        // Off the route the turn distances are measured from somewhere else: no warning.
        guard let nav = model.nav, !nav.isOffRoute else { return nil }
        let turn = nav.currentIndex + 1 < nav.steps.count ? nav.steps[nav.currentIndex + 1].symbol : ""
        let toTurn = nav.distanceToManoeuvre
        if turn.contains("left"), toTurn <= 60 { return .turnLeft(inMetres: toTurn) }
        if turn.contains("right"), toTurn <= 30 { return .turnRight(inMetres: toTurn) }
        guard let rider = model.route.riderCoordinate(at: now),
              let toJunction = model.lanePlan?.metresToJunction(at: rider), toJunction < toTurn - 10 else { return nil }
        return .straightThroughJunction(inMetres: toJunction)
    }

    private func panel(_ c: RouteConflict) -> some View {
        let name = switch c.track.cls {
        case .bicycle: "Cyclist"
        case .motorcycle: "Motorcycle"
        case .bus: "Bus"
        case .truck: "Truck"
        default: "Car"
        }
        let (icon, title, line): (String, String, String) = switch c {
        // Short titles: read in a glance at speed. The second line carries the advice.
        case .letPassBeforeLeft: ("arrow.turn.up.left", "\(name) on your left", "Let it pass before moving over")
        case .rightHookAtJunction: ("exclamationmark.triangle.fill", "\(name) overtaking", "May turn right at the junction")
        case .passingOnRight: ("arrow.turn.up.right", "\(name) on your right", "Let it go before turning")
        }
        return GuidanceCardShell(fill: Palette.amber) {
            GuidanceCardMessage(icon: icon, title: title, line: line, ink: Color(hex: 0x1B1300))
        }
    }
}
