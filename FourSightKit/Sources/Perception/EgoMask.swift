import Foundation

/// The bike's own parts, learned from the footage: the rear wheel sits under the camera,
/// pinned to the bottom edge, and the detector calls it a person or a car in about half
/// the frames of a real ride (263 of 480 sampled). Anything bottom-anchored, small, and
/// not moving in the image for `settle` seconds is part of the bike; from then on,
/// detections centred in that spot are dropped for the rest of the ride.
///
/// A vehicle is never masked by this: one that close fills far more of the frame than
/// `maxHeight`, and a road user that holds still in the image while the bike rides is
/// still moving through the world, so it only settles if it is also bottom-anchored.
public struct EgoMask: Sendable {
    /// A box's bottom within this fraction of the frame's bottom edge counts as anchored.
    public var anchorBand = 0.1
    /// Taller than this fraction of the frame is never a bike part.
    public var maxHeight = 0.35
    /// Centre drift, as a fraction of the frame, still counted as not moving.
    public var drift = 0.06
    public var settle = 2.0
    /// The detector sees the wheel in about half the frames; a gap this long keeps the
    /// candidate rather than starting the clock again.
    public var gap = 1.0
    /// Hits needed over `settle`, so two chance boxes cannot mask a spot.
    public var minHits = 8
    /// Learned zones, in frame fractions.
    public private(set) var zones: [DetectionFilter.Zone] = []
    /// Masked share of the frame above which the mount is too low to work: traffic behind
    /// the wheel goes unseen. shortcut: 0.2 is a starting guess (a wheel box a fifth of the
    /// frame each way masks ~0.08 once padded and clipped); tune it on more mounts.
    public var maxCoverage = 0.2

    /// Share of the frame the learned zones hide (overlaps counted twice, an upper bound).
    public var coverage: Double {
        zones.reduce(0) { $0 + max(0, min($1.x2, 1) - max($1.x1, 0)) * max(0, min($1.y2, 1) - max($1.y1, 0)) }
    }

    /// The wheel hides so much of the view that the rider should remount the phone.
    public var blocksView: Bool { coverage > maxCoverage }

    private var candidate: (cx: Double, cy: Double, w: Double, h: Double, since: Double, last: Double, hits: Int)?

    /// `zones` from an earlier ride: the mount does not move, so the wheel is known from
    /// the first frame instead of after a few seconds of riding.
    public init(zones: [DetectionFilter.Zone] = []) { self.zones = zones }

    /// Learns from this frame's detections and returns those not on a bike part.
    public mutating func apply(_ dets: [Detection], imageW: Double, imageH: Double, t: Double) -> [Detection] {
        func frac(_ b: Box) -> (cx: Double, cy: Double, w: Double, h: Double) {
            (b.cx / imageW, b.cy / imageH, b.w / imageW, b.h / imageH)
        }
        let anchored = dets.map { frac($0.box) }
            .filter { $0.cy + $0.h / 2 > 1 - anchorBand && $0.h < maxHeight }
        if var c = candidate, let same = anchored.first(where: { abs($0.cx - c.cx) < drift && abs($0.cy - c.cy) < drift }) {
            c.last = t; c.hits += 1
            c.w = max(c.w, same.w); c.h = max(c.h, same.h)
            candidate = c
            if t - c.since >= settle, c.hits >= minHits, !zones.contains(where: { inside(c.cx, c.cy, $0) }) {
                // Pad by a quarter of its size: the detector's box around the wheel wobbles.
                let pw = c.w * 0.75, ph = c.h * 0.75
                zones.append(.init(x1: c.cx - pw, y1: c.cy - ph, x2: c.cx + pw, y2: min(c.cy + ph, 1)))
                candidate = nil
            }
        } else if candidate == nil || t - candidate!.last > gap {
            candidate = anchored.first(where: { a in !zones.contains { inside(a.cx, a.cy, $0) } })
                .map { ($0.cx, $0.cy, $0.w, $0.h, t, t, 1) }
        }
        guard !zones.isEmpty else { return dets }
        return dets.filter { d in
            let f = frac(d.box)
            return !(f.h < maxHeight && zones.contains { inside(f.cx, f.cy, $0) })
        }
    }

    private func inside(_ x: Double, _ y: Double, _ z: DetectionFilter.Zone) -> Bool {
        x >= z.x1 && x <= z.x2 && y >= z.y1 && y <= z.y2
    }
}
