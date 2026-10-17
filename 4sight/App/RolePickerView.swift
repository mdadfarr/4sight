import SwiftUI

/// First-launch choice of which phone this is. Long-press anywhere on the role screen to change it.
struct RolePickerView: View {
    @AppStorage("role") private var role = ""

    var body: some View {
        Group {
            switch role {
            case "rear": RearView()
            case "front": FrontRootView()
            default: picker
            }
        }
        .onLongPressGesture(minimumDuration: 1.5) { role = "" }
        .preferredColorScheme(.dark)
    }

    private var picker: some View {
        VStack(spacing: 24) {
            Text("This phone is the")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(Theme.textDim)
            roleButton("Rear", symbol: "camera.fill", value: "rear")
            roleButton("Front", symbol: "bicycle", value: "front")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private func roleButton(_ title: String, symbol: String, value: String) -> some View {
        Button { role = value } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: 280, minHeight: 88)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
