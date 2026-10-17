import SwiftUI

/// Whether the rest of the bike is awake, shown on every screen before the ride.
///
/// A maps app has no reason for this strip. 4sight does: the rider must not find out
/// at speed that the rear phone never woke up, and the rear phone is the one whose
/// battery goes first because it is running the camera and the detector.
struct LinkStrip: View {
    let link: LinkState

    private var ready: Bool { link == .connected }

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(ready ? Theme.green : Theme.red)
                .frame(width: 8, height: 8)
            Text(ready ? "Rear phone ready" : "Rear phone not connected")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
            if !ready {
                Text(link == .searching ? "Looking…" : "Offline")
                    .font(.system(size: 13, design: .rounded))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(ready ? Theme.green : Theme.red)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((ready ? Theme.green : Theme.red).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 11))
    }
}
