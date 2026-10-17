import Foundation

public enum BLEIDs {
    public static let service = "5db17fa8-6860-4cd4-bd95-50e90510e072"
    public static let command = "2490e4c3-b5b8-40db-8ab6-8cc856e1fa31"
    public static let peripheralName = "4sight"
}

public enum BLECommand: Equatable, Sendable {
    case left(level: Int)
    case right(level: Int)
    case clear
    case heartbeat

    /// Exact ASCII written to the command characteristic, no terminator.
    public var ascii: String {
        switch self {
        case .left(let l): return "L\(min(max(l, 1), 3))"
        case .right(let l): return "R\(min(max(l, 1), 3))"
        case .clear: return "X"
        case .heartbeat: return "H"
        }
    }

    public var data: Data { Data(ascii.utf8) }

    /// Builds the command for a Decision-style (grip, level) pair; nil when nothing should fire.
    public static func from(grip: String, level: Int) -> BLECommand? {
        guard level >= 1 else { return nil }
        switch grip {
        case "L": return .left(level: level)
        case "R": return .right(level: level)
        default: return nil
        }
    }
}
