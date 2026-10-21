import Foundation

public enum BLEIDs {
    public static let service = "5db17fa8-6860-4cd4-bd95-50e90510e072"
    public static let command = "2490e4c3-b5b8-40db-8ab6-8cc856e1fa31"
    /// ESP32 -> phone, notify. Carries the handlebar button presses.
    public static let event = "0f343fab-5e83-41a9-afb1-07dc42818c5f"
}

public enum BLECommand: Equatable, Sendable {
    case left(level: Int)
    case right(level: Int)
    case clear
    case heartbeat
    /// Merge answer: that lane is clear (green button LED).
    case mergeClear(side: String)
    /// Merge answer: that lane is blocked (red button LED).
    case mergeBlocked(side: String)

    /// Exact ASCII written to the command characteristic, no terminator.
    public var ascii: String {
        switch self {
        case .left(let l): return "L\(min(max(l, 1), 3))"
        case .right(let l): return "R\(min(max(l, 1), 3))"
        case .clear: return "X"
        case .heartbeat: return "H"
        case .mergeClear(let s): return "G\(s == "R" ? "R" : "L")"
        case .mergeBlocked(let s): return "N\(s == "R" ? "R" : "L")"
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

/// What the ESP32 sends back on the event characteristic.
public enum BLEEvent: Equatable, Sendable {
    /// The rider pressed the button on this handlebar, asking about that lane.
    case mergeRequest(side: String)

    /// Parses one notify payload. Unknown payloads are ignored rather than guessed at.
    public static func parse(_ text: String) -> BLEEvent? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "ML": return .mergeRequest(side: "L")
        case "MR": return .mergeRequest(side: "R")
        default: return nil
        }
    }

    public static func parse(_ data: Data) -> BLEEvent? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }
}
