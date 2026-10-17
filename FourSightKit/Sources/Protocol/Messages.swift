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

public struct FrameMessage: Codable, Equatable, Sendable {
    public var t: Double
    public var fps: Int
    public var temp: ThermalLabel
    public var speed: Double
    public var heading: Double
    public var demo: Bool
    public var tracks: [TrackMessage]

    public init(t: Double, fps: Int, temp: ThermalLabel, speed: Double, heading: Double,
                demo: Bool, tracks: [TrackMessage]) {
        self.t = t; self.fps = fps; self.temp = temp; self.speed = speed
        self.heading = heading; self.demo = demo; self.tracks = tracks
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
