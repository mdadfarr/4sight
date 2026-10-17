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
    public var drift = 0.04
    public var settle = 2.0
    /// Learned zones, in frame fractions.
    public private(set) var zones: [DetectionFilter.Zone] = []

    private var candidate: (cx: Double, cy: Double, w: Double, h: Double, since: Double)?

    public init() {}

    /// Learns from this frame's detections and returns those not on a bike part.
    public mutating func apply(_ dets: [Detection], imageW: Double, imageH: Double, t: Double) -> [Detection] {
        func frac(_ b: Box) -> (cx: Double, cy: Double, w: Double, h: Double) {
            (b.cx / imageW, b.cy / imageH, b.w / imageW, b.h / imageH)
        }
        let anchored = dets.map { frac($0.box) }
            .filter { $0.cy + $0.h / 2 > 1 - anchorBand && $0.h < maxHeight }
        if let c = candidate, let same = anchored.first(where: { abs($0.cx - c.cx) < drift && abs($0.cy - c.cy) < drift }) {
            if t - c.since >= settle, !zones.contains(where: { inside(c.cx, c.cy, $0) }) {
                // Pad by a quarter of its size: the detector's box around the wheel wobbles.
                let pw = max(c.w, same.w) * 0.75, ph = max(c.h, same.h) * 0.75
                zones.append(.init(x1: c.cx - pw, y1: c.cy - ph, x2: c.cx + pw, y2: min(c.cy + ph, 1)))
                candidate = nil
            }
        } else {
            candidate = anchored.first(where: { a in !zones.contains { inside(a.cx, a.cy, $0) } })
                .map { ($0.cx, $0.cy, $0.w, $0.h, t) }
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
