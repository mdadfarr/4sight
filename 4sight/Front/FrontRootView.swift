import SwiftUI

// Placeholder on main; the real view arrives with front/synthetic-wedge.
struct FrontRootView: View {
    var body: some View {
        Text("Front role: coming")
            .foregroundStyle(Theme.textDim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
    }
}
