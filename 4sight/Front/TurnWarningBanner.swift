import Protocol
import SwiftUI
import ThreatEngine

/// The right-hook warning: in the last 60 m before a turn, a vehicle behind on that side
/// that will reach the rider first takes over the manoeuvre banner in amber. Navigation
/// knows the turn and the rear camera knows the vehicle; this is where they meet.
///
/// Held 1.5 s after the vehicle clears, so a track flickering out for a frame cannot make
/// the banner blink. The merge answer, drawn above it, still wins while it shows.
struct TurnWarningBanner: View {
    @ObservedObject var model: FrontModel
    @State private var hold = Hold()

    static let holdSeconds = 1.5

    /// Not observed: the timeline below redraws often enough to read it.
    private final class Hold {
        var vehicle: VehicleClass = .car
        var side: TurnSide = .right
        var until = Date.distantPast
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
            GeometryReader { geo in
                let scale = geo.size.width / Design.width
                if let shown = warning(at: timeline.date) {
                    panel(shown)
                        .frame(width: Design.width, height: Design.bannerH)
                        .scaleEffect(scale, anchor: .topLeading)
                        .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Re-evaluates the conflict for this moment and returns what to show, if anything.
    private func warning(at now: Date) -> (vehicle: VehicleClass, side: TurnSide)? {
        if model.link == .connected, let nav = model.nav, nav.currentIndex + 1 < nav.steps.count,
           let frame = model.frame {
            let symbol = nav.steps[nav.currentIndex + 1].symbol
            let side: TurnSide? = symbol.contains("right") ? .right : symbol.contains("left") ? .left : nil
            if let side, let hit = turnConflict(turn: side, metresToTurn: nav.distanceToManoeuvre, tracks: frame.tracks) {
                hold.vehicle = hit.cls; hold.side = side
                hold.until = now.addingTimeInterval(Self.holdSeconds)
            }
        }
        return now < hold.until ? (hold.vehicle, hold.side) : nil
    }

    private func panel(_ w: (vehicle: VehicleClass, side: TurnSide)) -> some View {
        let right = w.side == .right
        let name = switch w.vehicle {
        case .bicycle: "Cyclist"
        case .motorcycle: "Motorcycle"
        case .bus: "Bus"
        case .truck: "Truck"
        default: "Car"
        }
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Palette.amber)
            HStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name) on your \(right ? "right" : "left")")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Wait before turning \(right ? "right" : "left")")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .opacity(0.85)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color(hex: 0x1B1300))
            .padding(.leading, 26).padding(.trailing, 16)
            .padding(.top, 78)
        }
    }
}
