import Foundation

/// Pre-filters applied once, before any engine (port of the four filters in ml/danger.py):
/// too-small boxes, exclusion zones for the bike's own parts, large+unsure boxes, and a
/// sudden size jump (video cut or id swap) that should wipe that track's history.
public struct DetectionFilter: Sendable {
    /// Rectangle in frame fractions (0–1, top-left origin).
    public struct Zone: Equatable, Sendable {
        public var x1: Double, y1: Double, x2: Double, y2: Double
        public init(x1: Double, y1: Double, x2: Double, y2: Double) {
            self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
        }
        /// Parses "x1,y1,x2,y2" (launch-arg form); nil on anything else.
        public init?(_ text: String) {
            let v = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard v.count == 4 else { return nil }
            self.init(x1: v[0], y1: v[1], x2: v[2], y2: v[3])
        }
    }

    public var minWidthFraction = 0.04
    public var largeFraction = 0.5
    public var largeMinConfidence = 0.5
    public var jumpRatio = 1.6
    public var exclusionZones: [Zone] = []
    private var lastWidth: [Int: Double] = [:]

    public init() {}

    public func keep(_ d: Detection, imageW: Double, imageH: Double) -> Bool {
        let wf = d.box.w / imageW
        if wf < minWidthFraction { return false }
        if wf >= largeFraction && d.confidence < largeMinConfidence { return false }
        let fx = d.box.cx / imageW, fy = d.box.cy / imageH
        return !exclusionZones.contains { fx >= $0.x1 && fx <= $0.x2 && fy >= $0.y1 && fy <= $0.y2 }
    }

    public func apply(_ dets: [Detection], imageW: Double, imageH: Double) -> [Detection] {
        dets.filter { keep($0, imageW: imageW, imageH: imageH) }
    }

    /// Call once per frame per live track; true when the width changed by more than
    /// `jumpRatio` since last frame, i.e. the caller should reset that id's estimators.
    public mutating func jumped(id: Int, box: Box, imageW: Double) -> Bool {
        let wf = box.w / imageW
        defer { lastWidth[id] = wf }
        guard let prev = lastWidth[id], prev > 0 else { return false }
        let r = wf / prev
        return r > jumpRatio || r < 1 / jumpRatio
    }

    public mutating func forget(except live: Set<Int>) {
        lastWidth = lastWidth.filter { live.contains($0.key) }
    }
}
