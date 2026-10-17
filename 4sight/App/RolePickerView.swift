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
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            // Placeholder until the logo lands: swap this tile for the asset.
            RoundedRectangle(cornerRadius: 24)
                .fill(Light.blue)
                .frame(width: 88, height: 88)
                .overlay(Image(systemName: "eye.fill").font(.system(size: 38, weight: .semibold)).foregroundStyle(.white))
                .shadow(color: Light.blue.opacity(0.3), radius: 12, y: 6)
            Text("4sight")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(Light.ink)
                .padding(.top, 18)
            Text("See what\u{2019}s coming from behind.")
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(Light.dim)
                .padding(.top, 4)

            Spacer(minLength: 20)
            Text("Where is this phone going?")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Light.ink)
                .padding(.bottom, 16)
            HStack(spacing: 12) {
                choice("front", title: "Handlebar", detail: "Maps and alerts", symbol: "bicycle")
                choice("rear", title: "Rear rack", detail: "Watches behind you", symbol: "camera.fill")
            }

            Spacer(minLength: 20)
            Text("Choose the other one on your second phone.\nThey pair on their own.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Light.dim)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Light.sheet)
        .preferredColorScheme(.light)
    }

    /// One role, in the Places circles' style from the home screen.
    private func choice(_ value: String, title: String, detail: String, symbol: String) -> some View {
        let last = lastRole == value
        return Button {
            lastRole = value
            role = value
        } label: {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(last ? .white : Light.blue)
                    .frame(width: 72, height: 72)
                    .background(last ? Light.blue : Light.blueSoft, in: Circle())
                VStack(spacing: 2) {
                    Text(title).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Light.ink)
                    Text(detail).font(.system(size: 14, design: .rounded)).foregroundStyle(Light.dim)
                }
                Text(last ? "Last used" : " ")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Light.blue)
            }
            .padding(.top, 22).padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(last ? Light.blue : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(detail)")
    }
}
