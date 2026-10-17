import Foundation
import Protocol

/// The scripted ride from `docs/mock/front.html` (`CUES`), emitted at 20 Hz as real
/// FrameMessages so the screen is driven by the same path as the rear phone.
///
/// Every cue stays behind the rider: the camera has nothing to say about what is
/// alongside or ahead, so nothing is generated there.
final class SyntheticFeed: TrackFeed {
    struct Cue {
        let id: Int
        let cls: VehicleClass
        let from, to: Double
        let x0, x1, z0, z1: Double
        var level: Int = 0
        /// First `z < below` wins; nothing matched means level 0.
        var thresholds: [(below: Double, level: Int)] = []
        var vru = false
        var turnR = false
    }

    static let loop = 21.0

    /// Scripted presses of the handlebar merge buttons, so the banner demos with no
    /// ESP32 and no rear phone. `at` is when the answer was computed; the banner
    /// drops itself 3 s later, exactly as it would from a real answer.
    ///
    /// The blocked one is answered while cue 6 — the cyclist overtaking on the left —
    /// is still alongside, so the ring lands on a vehicle that is actually on screen.
    struct MergeCue {
        let at: Double
        let side: String
        let clear: Bool
        let blockedBy: Int?
    }

    static let mergeCues: [MergeCue] = [
        MergeCue(at: 9.5, side: "L", clear: false, blockedBy: 6),
        MergeCue(at: 16.5, side: "R", clear: true, blockedBy: nil),
    ]

    static let cues: [Cue] = [
        Cue(id: 1, cls: .car, from: 0, to: 6, x0: -1.5, x1: -1.5, z0: 38, z1: 0.5,
            thresholds: [(0, 0), (7, 3), (13, 2), (22, 1)]),
        Cue(id: 2, cls: .bus, from: 6, to: 10.5, x0: -4.1, x1: -4.1, z0: 38, z1: 9, level: 1),
        Cue(id: 3, cls: .car, from: 10.5, to: 14, x0: -2.2, x1: -1.3, z0: 34, z1: 3,
            level: 2, turnR: true),
        // A faster rider overtaking you on the left, 0.95 m off: grey normally, an
        // alert only in demo mode, because ThreatEngine ignores bicycles outside it.
        Cue(id: 6, cls: .bicycle, from: 6, to: 14, x0: -0.95, x1: -0.95, z0: 18, z1: 0.6,
            thresholds: [(0, 0), (4, 3), (8, 2), (14, 1)], vru: true),
        // Pedestrians stand still in the world, so riding away from them they recede
        // at riding speed: someone out of a parked car, and two on the pavements.
        Cue(id: 4, cls: .person, from: 13.5, to: 17.5, x0: 1.95, x1: 1.35,
            z0: 3.5, z1: 3.5 + 4 * 3.6, thresholds: [(6, 2), (9, 1)], vru: true),
        Cue(id: 7, cls: .person, from: 12, to: 17, x0: 5.4, x1: 5.4,
            z0: 7, z1: 7 + 5 * (3.6 - 1.3), vru: true),
        Cue(id: 8, cls: .person, from: 12.5, to: 16.5, x0: 6.3, x1: 6.3,
            z0: 9, z1: 9 + 4 * (3.6 + 1.4), vru: true),
        // Safe passes, the common case: a car a full lane over and a slow truck in the
        // far lane. Seen, drawn grey, no edge glow and no buzz.
        Cue(id: 9, cls: .car, from: 1, to: 6, x0: -4.6, x1: -4.6, z0: 36, z1: 1, level: 0),
        Cue(id: 10, cls: .truck, from: 13, to: 21, x0: -4.4, x1: -4.4, z0: 34, z1: 14, level: 0),
        // Straight behind: no side to steer towards, so the whole frame carries it.
        Cue(id: 5, cls: .car, from: 17.5, to: 21, x0: -0.25, x1: -0.25, z0: 24, z1: 2,
            thresholds: [(6, 3), (12, 2), (20, 1)]),
    ]

    let frames: AsyncStream<FrameMessage>
    private let continuation: AsyncStream<FrameMessage>.Continuation
    private let freeze: Double?
    private let demo: Bool
    private var task: Task<Void, Never>?

    init(freeze: Double? = nil, demo: Bool = false) {
        self.freeze = freeze
        self.demo = demo
        var cont: AsyncStream<FrameMessage>.Continuation!
        frames = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        continuation = cont
    }

    func start() {
        if let freeze {
            continuation.yield(frame(at: freeze))
            return
        }
        let origin = Date()
        task = Task { [weak self] in
            while !Task.isCancelled, let self {
                continuation.yield(frame(at: Date().timeIntervalSince(origin)))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func stop() { task?.cancel() }

    func frame(at time: Double) -> FrameMessage {
        let t = time.truncatingRemainder(dividingBy: Self.loop)
        var tracks: [TrackMessage] = []
        for cue in Self.cues where t >= cue.from && t <= cue.to {
            let f = (t - cue.from) / max(cue.to - cue.from, 0.001)
            let z = cue.z0 + (cue.z1 - cue.z0) * f
            let x = cue.x0 + (cue.x1 - cue.x0) * f

            var level = cue.level
            if !cue.thresholds.isEmpty && (!cue.vru || demo) {
                level = 0
                for step in cue.thresholds where z < step.below {
                    level = step.level
                    break
                }
            }
            if cue.vru && !demo { level = 0 }

            tracks.append(TrackMessage(
                id: cue.id, cls: cue.cls, x: x, z: z, invTTC: 0, gapPred: abs(x),
                level: level, grip: x < -0.8 ? "L" : x > 0.8 ? "R" : "-", turnR: cue.turnR))
        }
        // The newest answer still inside its window, on the same clock the front
        // measures it against.
        let answer = Self.mergeCues.last { t >= $0.at && t - $0.at < MergeBanner.window }
        let merge = answer.map {
            MergeMessage(side: $0.side, clear: $0.clear, blockedBy: $0.blockedBy,
                         t: time - (t - $0.at))
        }
        return FrameMessage(t: time, fps: 10, temp: .nominal, speed: World.speed,
                            heading: -1, demo: demo, tracks: tracks, merge: merge)
    }
}
