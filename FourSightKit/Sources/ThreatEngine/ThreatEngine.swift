import Foundation
import Protocol

public struct TrackState: Equatable, Sendable {
    public var id: Int
    public var cls: VehicleClass
    public var z: Double
    /// Signed sideways offset, metres, negative = rider's left.
    public var gap: Double
    public var gapVelocity: Double
    public var invTTC: Double
    public var turnR: Bool
    public var framesSeen: Int

    public init(id: Int, cls: VehicleClass, z: Double, gap: Double, gapVelocity: Double = 0,
                invTTC: Double, turnR: Bool = false, framesSeen: Int = 1) {
        self.id = id; self.cls = cls; self.z = z; self.gap = gap; self.gapVelocity = gapVelocity
        self.invTTC = invTTC; self.turnR = turnR; self.framesSeen = framesSeen
    }
}

public struct Decision: Equatable, Sendable {
    public var id: Int
    public var level: Int
    public var grip: String
    /// Absolute predicted passing gap, metres (0 for right-hook holds of absent tracks).
    public var gapPred: Double

    public init(id: Int, level: Int, grip: String, gapPred: Double = 0) {
        self.id = id; self.level = level; self.grip = grip; self.gapPred = gapPred
    }
}

public struct ThreatConfig: Sendable {
    public var gapAlert = 1.0
    public var gapAlertLarge = 1.5
    public var gapCaution = 1.5
    public var aReqImminent = 3.0
    public var debounceFrames = 4
    /// When DangerEngine independently rates the track warning or worse (Fusion): two
    /// estimators that fail differently agreeing for 0.2 s beats one agreeing for 0.4 s,
    /// and 2 still keeps a single glitched frame out.
    public var corroboratedDebounceFrames = 2
    public var slowVehicleSpeed = 2.8
    public var rightHookHold = 3.0
    public var closingInvTTC = 0.02
    /// Demo mode only: a person or bicycle counts as closing above this speed (m/s), so a
    /// runner alerts but someone fidgeting or strolling a few metres behind does not. Up close
    /// a small change in a person's box reads as a big invTTC; cars do not change shape.
    public var demoClosingSpeed = 2.0
    public var rightHookNearZ = 15.0
    public var forgetAfter = 60.0
    /// Gap prediction clamps: a lane change is ~1-1.5 m/s sideways, and past 3 s the
    /// extrapolation is noise (a fast lateral pass at TTC 20 s predicted 45-212 m).
    public var maxGapVelocity = 1.5
    public var maxPredictTTC = 3.0
    public init() {}
}

public final class ThreatEngine {
    private struct Memory {
        var consecutive = 0
        var rightHookUntil = -Double.infinity
        var lastSeen: TimeInterval
    }

    /// `var` so the rear phone can re-time the debounce when it changes detection rate.
    public var config: ThreatConfig
    private var memory: [Int: Memory] = [:]

    public init(config: ThreatConfig = ThreatConfig()) { self.config = config }

    /// `corroborated`: ids DangerEngine also flags this frame (Fusion.corroborated); they
    /// confirm after `corroboratedDebounceFrames` instead of `debounceFrames`.
    public func update(tracks: [TrackState], bikeSpeed: Double, demoMode: Bool,
                       now: TimeInterval, corroborated: Set<Int> = []) -> [Decision] {
        let cfg = config
        var out: [Decision] = []
        var seen = Set<Int>()

        for t in tracks {
            switch t.cls {
            case .bicycle, .person: if !demoMode { continue }
            default: break
            }
            seen.insert(t.id)
            var mem = memory[t.id] ?? Memory(lastSeen: now)
            mem.lastSeen = now

            var level = 0
            var grip = "-"
            var gapPred = abs(t.gap)
            let onFoot = t.cls == .person || t.cls == .bicycle
            let closing = t.invTTC > cfg.closingInvTTC && (!onFoot || t.z * t.invTTC >= cfg.demoClosingSpeed)
            if closing {
                let ttc = 1 / t.invTTC
                let v = min(max(t.gapVelocity, -cfg.maxGapVelocity), cfg.maxGapVelocity)
                gapPred = abs(t.gap + v * min(ttc, cfg.maxPredictTTC))
                let threshold = (t.cls == .bus || t.cls == .truck) ? cfg.gapAlertLarge : cfg.gapAlert
                // bikeSpeed 0 = no GPS fix yet (or simulator): speed unknown, never "slow".
                let slow = bikeSpeed > 0 && bikeSpeed + t.z * t.invTTC < cfg.slowVehicleSpeed
                if gapPred <= threshold {
                    level = t.z / (2 * ttc * ttc) >= cfg.aReqImminent ? 3 : 2
                    grip = "L"
                } else if gapPred <= cfg.gapCaution && !slow {
                    level = 1
                }
            }
            let rightHook = t.turnR && (closing || t.z < cfg.rightHookNearZ)
            if rightHook || mem.rightHookUntil > now {
                level = max(level, 2)
                grip = "R"
            }

            mem.consecutive = level >= 2 ? mem.consecutive + 1 : 0
            let need = corroborated.contains(t.id) ? cfg.corroboratedDebounceFrames : cfg.debounceFrames
            if level >= 2 && mem.consecutive < need { level = 1 }

            if level >= 2 {
                if rightHook { mem.rightHookUntil = now + cfg.rightHookHold }
                // The level is the threat as it stands, every frame, so the screen stays red
                // for as long as the danger lasts. Buzzing once per car is the haptics' job
                // (RearWorker.driveHaptics sends only when a car first escalates).
            }
            if level < 2 { grip = "-" }

            memory[t.id] = mem
            out.append(Decision(id: t.id, level: level, grip: grip, gapPred: gapPred))
        }

        for (id, mem) in memory where !seen.contains(id) {
            if now - mem.lastSeen > cfg.forgetAfter {
                memory[id] = nil
            } else if mem.rightHookUntil > now {
                out.append(Decision(id: id, level: 2, grip: "R"))
            }
        }
        return out
    }
}
