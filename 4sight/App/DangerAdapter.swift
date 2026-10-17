import Foundation
import Perception
import Protocol
import ThreatEngine

/// Feeds Arshiya's DangerEngine from our tracks and returns its per-track verdicts as
/// votes for Fusion. The engine gets RAW image-frame x: its `mirror` flag does the
/// left/right flip, nobody else.
nonisolated final class DangerAdapter {
    private let engine: DangerEngine

    init() {
        var c = DangerConfig()
        c.frameWidth = 1; c.frameHeight = 1; c.mirror = true   // inputs are frame fractions
        engine = DangerEngine(config: c)
    }

    /// Run every frame, even with no tracks, so the engine's per-track windows age out.
    func votes(tracks: [Track], t: Double, imageW w: Double, imageH h: Double) -> [Int: DangerVote] {
        // Box is top-left origin already, so cy/h is the "1 - midY" her README asks for.
        // Confidence 1: DetectionFilter already dropped large+unsure boxes upstream.
        let dets = tracks.map {
            DangerDetection(trackID: $0.id, centerX: $0.box.cx / w, width: $0.box.w / w,
                            centerY: $0.box.cy / h, confidence: 1)
        }
        // `vehicles` is this frame's per-track verdict, before the per-side 1 s hold, so a
        // vote never outlives the evidence for that track.
        let out = engine.update(time: t, detections: dets)
        return Dictionary(out.vehicles.map { ($0.trackID, DangerVote(level: $0.level, side: $0.side)) },
                          uniquingKeysWith: { a, _ in a })
    }
}
