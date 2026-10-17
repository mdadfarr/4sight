import Foundation
import Protocol

/// Scripted 20 Hz frames driven by a clock `t`. Scenario 0 loops every 17 s.
final class SyntheticFeed: TrackFeed {
    /// One track moving linearly in z over [t0, t1). `level == nil` means derive from z.
    struct Segment {
        let t0, t1: Double
        let id: Int
        let cls: VehicleClass
        let x: Double
        let z0, z1: Double
        let level: Int?
        var turnR = false
    }

    static let scenarios: [[Segment]] = [
        [
            Segment(t0: 0, t1: 6, id: 1, cls: .car, x: -0.8, z0: 40, z1: -5, level: nil),
            Segment(t0: 6, t1: 10, id: 2, cls: .bus, x: -1.6, z0: 30, z1: 5, level: 1),
            Segment(t0: 10, t1: 14, id: 3, cls: .car, x: 0.6, z0: 25, z1: 4, level: 2, turnR: true),
            Segment(t0: 14, t1: 17, id: 4, cls: .person, x: 0.3, z0: 6, z1: 6, level: 0),
        ],
    ]

    let frames: AsyncStream<FrameMessage>
    private let continuation: AsyncStream<FrameMessage>.Continuation
    private let segments: [Segment]
    private let freeze: Double?
    private var task: Task<Void, Never>?

    init(scenario: Int = 0, freeze: Double? = nil) {
        segments = Self.scenarios[min(max(scenario, 0), Self.scenarios.count - 1)]
        self.freeze = freeze
        var cont: AsyncStream<FrameMessage>.Continuation!
        frames = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        continuation = cont
    }

    func start() {
        if let freeze {
            continuation.yield(frame(at: freeze))
            return
        }
        let start = Date()
        task = Task { [weak self] in
            while !Task.isCancelled, let self {
                continuation.yield(frame(at: Date().timeIntervalSince(start)))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func stop() { task?.cancel() }

    func frame(at t: Double) -> FrameMessage {
        let loopLength = segments.map(\.t1).max() ?? 1
        let tt = t.truncatingRemainder(dividingBy: loopLength)
        let tracks = segments.filter { $0.t0 <= tt && tt < $0.t1 }.map { s -> TrackMessage in
            let f = (tt - s.t0) / (s.t1 - s.t0)
            let z = s.z0 + (s.z1 - s.z0) * f
            return TrackMessage(id: s.id, cls: s.cls, x: s.x, z: z, invTTC: 0, gapPred: abs(s.x),
                                level: s.level ?? Self.levelByRange(z), grip: "-", turnR: s.turnR)
        }
        return FrameMessage(t: t, fps: 10, temp: .nominal, speed: 5.3, heading: -1, demo: false, tracks: tracks)
    }

    /// Overtake script: 0 → 1 (z < 20) → 2 (z < 12) → 3 (z < 8) → 0 once past (z < 0).
    static func levelByRange(_ z: Double) -> Int {
        switch z {
        case ..<0: return 0
        case ..<8: return 3
        case ..<12: return 2
        case ..<20: return 1
        default: return 0
        }
    }
}
