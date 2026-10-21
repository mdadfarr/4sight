import SwiftUI

/// Rear screen colours. Dark only.
enum Theme {
    static let bg = Color(hex: 0x0B0D10)
    static let ground = Color(hex: 0x171B21)
    static let line = Color(hex: 0x2A313B)
    static let edge = Color(hex: 0xB5BCC6)
    static let amber = Color(hex: 0xFFB020)
    static let red = Color(hex: 0xFF3B30)
    static let text = Color(hex: 0xF2F4F7)
    static let textDim = Color(hex: 0xA6ADB8)
    static let green = Color(hex: 0x34C759)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
