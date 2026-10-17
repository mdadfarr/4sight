import Foundation
import Perception
import Protocol
import ThreatEngine

/// Feeds Arshiya's DangerEngine from our tracks and maps its per-side levels back into
/// per-track Decisions (for FrameMessage/overlay) plus two side Decisions (for the grips).
/// The engine gets RAW image-frame x: its `mirror` flag does the left/right flip, nobody else.
nonisolated final class DangerAdapter {
    static let leftID = -1, rightID = -2
    private let engine: DangerEngine

    init() {
        var c = DangerConfig()
        c.frameWidth = 1; c.frameHeight = 1; c.mirror = true   // inputs are frame fractions
        engine = DangerEngine(config: c)
    }

    /// `gaps`: rider-frame sideways gap per track id (GapEstimator), so FrameMessage.gap_pred
    /// shows the same number as the ThreatEngine path. shortcut: current gap, no velocity term.
    func update(tracks: [Track], gaps: [Int: Double], t: Double, imageW w: Double, imageH h: Double)
        -> (perTrack: [Decision], sides: [Decision]) {
        // Box is top-left origin already, so cy/h is the "1 - midY" her README asks for.
        // Confidence 1: DetectionFilter already dropped large+unsure boxes upstream.
        let dets = tracks.map {
            DangerDetection(trackID: $0.id, centerX: $0.box.cx / w, width: $0.box.w / w,
                            centerY: $0.box.cy / h, confidence: 1)
        }
        let out = engine.update(time: t, detections: dets)
        let perTrack = tracks.map { tr -> Decision in
            let side = Self.side(frac: tr.box.cx / w, mirror: true)
            let level: AlertLevel
            switch side {
            case .left: level = out.left
            case .right: level = out.right
            case .both: level = max(out.left, out.right)
            }
            // shortcut: a track dead behind (.both) is reported on the left grip, firmware's priority side
            return Decision(id: tr.id, level: level.rawValue, grip: level == .off ? "-" : (side == .right ? "R" : "L"),
                            gapPred: abs(gaps[tr.id] ?? 0))
        }
        var sides: [Decision] = []
        if out.left != .off { sides.append(Decision(id: Self.leftID, level: out.left.rawValue, grip: "L")) }
        if out.right != .off { sides.append(Decision(id: Self.rightID, level: out.right.rawValue, grip: "R")) }
        return (perTrack, sides)
    }

    /// Same thirds rule as DangerEngine.sideFor (private there).
    static func side(frac: Double, mirror: Bool) -> Side {
        if frac >= 1.0 / 3.0 && frac <= 2.0 / 3.0 { return .both }
        let imageLeft = frac < 1.0 / 3.0
        return imageLeft ? (mirror ? .right : .left) : (mirror ? .left : .right)
    }
}
