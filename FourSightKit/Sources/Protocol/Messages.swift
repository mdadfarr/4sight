import Foundation

public enum ThermalLabel: String, Codable, Sendable {
    case nominal, fair, serious, critical
}

public enum VehicleClass: String, Codable, Sendable, CaseIterable {
    case car, truck, bus, motorcycle, bicycle, person

    /// Typical vehicle length in metres, used to project the gap to the vehicle's near corner.
    public var length: Double {
        switch self {
        case .car: return 4.5
        case .truck: return 8
        case .bus: return 12
        case .motorcycle: return 2.2
        case .bicycle: return 1.8
        case .person: return 0.5
        }
    }
}

public struct TrackMessage: Codable, Equatable, Sendable {
    public var id: Int
    public var cls: VehicleClass
    public var x: Double
    public var z: Double
    public var invTTC: Double
    public var gapPred: Double
    public var level: Int
    public var grip: String
    public var turnR: Bool

    enum CodingKeys: String, CodingKey {
        case id, cls, x, z, level, grip
        case invTTC = "inv_ttc"
        case gapPred = "gap_pred"
        case turnR = "turn_r"
    }

    public init(id: Int, cls: VehicleClass, x: Double, z: Double, invTTC: Double,
                gapPred: Double, level: Int, grip: String, turnR: Bool) {
        self.id = id; self.cls = cls; self.x = x; self.z = z; self.invTTC = invTTC
        self.gapPred = gapPred; self.level = level; self.grip = grip; self.turnR = turnR
    }
}

/// The answer to one handlebar merge button press, carried to the front phone.
/// The front shows it for 3 s from `t` and then drops it; it is never latched.
public struct MergeMessage: Codable, Equatable, Sendable {
    /// "L" or "R", the lane the rider asked about.
    public var side: String
    public var clear: Bool
    public var blockedBy: Int?
    /// Rear-phone time the answer was computed.
    public var t: Double

    public init(side: String, clear: Bool, blockedBy: Int? = nil, t: Double) {
        self.side = side; self.clear = clear; self.blockedBy = blockedBy; self.t = t
    }

    private enum CodingKeys: String, CodingKey {
        case side, clear, t
        case blockedBy = "blocked_by"
    }
}

public struct FrameMessage: Codable, Equatable, Sendable {
    public var t: Double
    public var fps: Int
    public var temp: ThermalLabel
    public var speed: Double
    public var heading: Double
    public var demo: Bool
    public var tracks: [TrackMessage]
    /// The most recent merge answer, absent until the rider presses a bar button.
    /// Optional on the wire: an older front build simply ignores it.
    public var merge: MergeMessage?
    /// Whether the rear phone has the handlebar grips: "connected" or "searching".
    /// Optional on the wire, like `merge`: absent from older rear builds.
    public var grips: String?
    /// Rear phone battery, 0–1, absent when iOS does not report it.
    public var battery: Double?
    /// True when the bike's own wheel hides too much of the rear camera's view (EgoMask);
    /// absent otherwise, and from older rear builds.
    public var wheelBlocksView: Bool?

    enum CodingKeys: String, CodingKey {
        case t, fps, temp, speed, heading, demo, tracks, merge, grips, battery
        case wheelBlocksView = "wheel_blocks_view"
    }

    public init(t: Double, fps: Int, temp: ThermalLabel, speed: Double, heading: Double,
                demo: Bool, tracks: [TrackMessage], merge: MergeMessage? = nil,
                grips: String? = nil, battery: Double? = nil, wheelBlocksView: Bool? = nil) {
        self.t = t; self.fps = fps; self.temp = temp; self.speed = speed
        self.heading = heading; self.demo = demo; self.tracks = tracks; self.merge = merge
        self.grips = grips; self.battery = battery; self.wheelBlocksView = wheelBlocksView
    }

    /// One JSON object terminated by "\n", the wire format of the rear→front link.
    public func encodeLine() throws -> Data {
        var data = try JSONEncoder().encode(self)
        data.append(0x0A)
        return data
    }

    public static func decode(line: Data) throws -> FrameMessage {
        try JSONDecoder().decode(FrameMessage.self, from: line)
    }

    public static func decode(line: String) throws -> FrameMessage {
        try decode(line: Data(line.utf8))
    }
}
