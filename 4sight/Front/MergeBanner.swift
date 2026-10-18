import Protocol
import SwiftUI

/// The answer to a handlebar merge button: may I move into the lane on this side?
///
/// Deliberately nothing like the edge warning. The warning is a soft gradient with no
/// words that flashes in from the screen edge and is about something the rider did not
/// ask for. This is a solid, steady, lettered panel inset from the edge, answering a
/// question the rider just asked, and it never flashes. Green or red matches the LED
/// lighting on that grip at the same moment, so the bar and the screen agree.
enum MergeBanner {

    /// CONTRACTS.md: shown for 3 s from `merge.t`, then dropped, never latched.
    static let window = 3.0

    /// Green reads as green against the map without being the lane-pill green; the
    /// blocked red is darker than the level-3 alert red so a glance can tell a
    /// standing answer from a flashing warning.
    static let clearFill = Color(hex: 0x12874A)
    static let blockedFill = Color(hex: 0xC1271D)

    /// The answer to show right now, or nil. Measured on the rear phone's clock,
    /// because `merge.t` and `frame.t` are both rear-phone time; the front's own
    /// clock never enters into it.
    ///
    /// A stale link drops the banner too: the last frame would otherwise hold an
    /// answer on screen indefinitely, which is exactly the latching the contract
    /// forbids.
    static func current(_ frame: FrameMessage?, link: LinkState) -> MergeMessage? {
        guard link == .connected, let frame, let merge = frame.merge else { return nil }
        let age = frame.t - merge.t
        return age >= 0 && age < window ? merge : nil
    }
}

/// The answer turns the guidance card green or red for its 3 s: the one place the rider
/// already looks, solid to match the LEDs on that grip, never flashing, so it cannot be
/// mistaken for the edge warning.
struct MergeBannerView: View {
    @ObservedObject var model: FrontModel

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / Design.width
            if let merge = MergeBanner.current(model.frame, link: model.link) {
                panel(merge)
                    .atGuidanceCard()
                    .scaleEffect(scale, anchor: .topLeading)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: MergeBanner.current(model.frame, link: model.link))
        .allowsHitTesting(false)
    }

    private func panel(_ merge: MergeMessage) -> some View {
        let left = merge.side == "L"
        return GuidanceCardShell(fill: merge.clear ? MergeBanner.clearFill : MergeBanner.blockedFill) {
            GuidanceCardMessage(
                icon: merge.clear ? (left ? "arrow.turn.up.left" : "arrow.turn.up.right") : "hand.raised.fill",
                title: merge.clear ? "Clear" : "Danger",
                line: merge.clear ? "Safe to merge \(left ? "left" : "right")" : nil,
                ink: .white)
        }
    }
}
