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

struct MergeBannerView: View {
    @ObservedObject var model: FrontModel

    var body: some View {
        if let merge = MergeBanner.current(model.frame, link: model.link) {
            let left = merge.side == "L"
            HStack(spacing: 0) {
                if !left { Spacer(minLength: 0) }
                panel(merge, left: left)
                if left { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
        }
    }

    private func panel(_ merge: MergeMessage, left: Bool) -> some View {
        VStack(spacing: 7) {
            Image(systemName: merge.clear
                  ? (left ? "arrow.turn.up.left" : "arrow.turn.up.right")
                  : "hand.raised.fill")
                .font(.system(size: 27, weight: .bold))
            Text(merge.clear ? "CLEAR" : "BLOCKED")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .kerning(1.2)
            Text(left ? "LEFT" : "RIGHT")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .kerning(1.6)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(width: 104)
        .padding(.vertical, 22)
        .background(merge.clear ? MergeBanner.clearFill : MergeBanner.blockedFill,
                    in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.9), lineWidth: 2.5))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
    }
}
