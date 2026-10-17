import SwiftUI

/// The first screen on every launch: which phone is this? One tap, the last choice marked,
/// so the set-up is "open the app on both phones, pick front and rear, mount them".
/// Asking each time (rather than remembering) means swapping phones never needs a hidden
/// gesture. `-role front|rear` skips it, for the simulator scripts.
struct RolePickerView: View {
    @State private var role = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["role"] as? String ?? ""
    @AppStorage("lastRole") private var lastRole = ""

    var body: some View {
        switch role {
        case "rear": RearView().preferredColorScheme(.dark)
        case "front": FrontRootView()
        default: picker
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            HStack(spacing: 10) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Light.blue)
                Text("4sight").font(.system(size: 34, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Light.ink)
            Text("Eyes behind you, on every ride.")
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(Light.dim)
                .padding(.top, 6)

            Text("This phone goes…")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Light.ink)
                .padding(.top, 44).padding(.bottom, 14)

            VStack(spacing: 14) {
                card("front", title: "On the handlebar", detail: "Navigation and warnings. Your everyday phone.",
                     symbol: "iphone.gen3", badge: "bicycle")
                card("rear", title: "On the rear rack", detail: "Camera facing back, watching the road behind you.",
                     symbol: "camera.fill", badge: "arrow.uturn.backward")
            }

            Spacer(minLength: 24)
            Text("Pick the other one on the second phone. They find each other on their own.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Light.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22).padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Light.sheet)
        .preferredColorScheme(.light)
    }

    private func card(_ value: String, title: String, detail: String, symbol: String, badge: String) -> some View {
        let last = lastRole == value
        return Button {
            lastRole = value
            role = value
        } label: {
            HStack(spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Light.blue)
                        .frame(width: 64, height: 64)
                        .background(Light.blueSoft, in: RoundedRectangle(cornerRadius: 18))
                    Image(systemName: badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Light.blue, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: 6, y: 6)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Light.ink)
                        if last {
                            Text("Last time")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Light.blue)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Light.blueSoft, in: Capsule())
                        }
                    }
                    Text(detail).font(.system(size: 14.5, design: .rounded)).foregroundStyle(Light.dim)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(Light.faint)
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(last ? Light.blue : .clear, lineWidth: 2))
            .shadow(color: Light.shadow.opacity(0.5), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}
