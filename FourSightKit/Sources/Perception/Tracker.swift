import Foundation
import Protocol

/// ByteTrack-lite: greedy IoU matching, high-confidence detections first, then low.
public final class Tracker {
    private struct Slot {
        var id: Int
        var cls: VehicleClass
        var kf: KalmanBox
        var hits = 1
        var misses = 0
        var age = 1
    }

    public var iouThreshold = 0.2   // ByteTrack match_thresh 0.8 on 1-IoU cost
    /// Second (low-confidence) pass; looser so glare-jittered boxes still re-attach.
    public var lowIouThreshold = 0.2
    public var highConfidence = 0.5
    public var lowConfidence = 0.1
    public var minHits = 2
    public var maxMisses = 15   // 1.5 s at 10 fps
    /// Third pass for whatever IoU missed: a person close to the lens moves further than
    /// their own width between 10 fps frames. Re-attach by centre distance, in box sizes.
    public var maxCentreJump = 0.75

    private var slots: [Slot] = []
    private var nextID = 1
    /// Ids handed out so far (fragmentation metric for ReplayBoxes).
    public var allocatedIDs: Int { nextID - 1 }

    public init() {}

    public func update(detections: [Detection], dt: Double) -> [Track] {
        for i in slots.indices {
            slots[i].kf.predict(dt: dt)
            slots[i].age += 1
        }
        let high = detections.filter { $0.confidence >= highConfidence }
        let low = detections.filter { $0.confidence >= lowConfidence && $0.confidence < highConfidence }

        var free = Set(slots.indices)
        var unmatchedHigh = match(high, free: &free, minIoU: iouThreshold)
        _ = match(low, free: &free, minIoU: lowIouThreshold)
        unmatchedHigh = matchByCentre(unmatchedHigh, high, free: &free)

        for i in free {
            slots[i].misses += 1
        }
        slots.removeAll { $0.misses > maxMisses }

        unmatchedHigh.sort { high[$0].confidence > high[$1].confidence }
        var seen = slots.filter { $0.misses == 0 }.map(\.kf.box)
        for d in unmatchedHigh.map({ high[$0] }) {
            // A second box on something already tracked this frame is the detector
            // double-firing, not a new object.
            if seen.contains(where: { Self.covered(d.box, by: $0) }) { continue }
            slots.append(Slot(id: nextID, cls: d.cls, kf: KalmanBox(box: d.box)))
            seen.append(d.box)
            nextID += 1
        }
        dropDuplicates()

        return slots.filter { $0.hits >= minHits }.map {
            Track(id: $0.id, cls: $0.cls, box: $0.kf.box, hits: $0.hits, misses: $0.misses, age: $0.age)
        }
    }

    /// Greedy nearest-centre assignment of detections IoU could not place, within
    /// `maxCentreJump` box sizes and a 2x size change. Returns the still-unmatched indices.
    private func matchByCentre(_ idx: [Int], _ dets: [Detection], free: inout Set<Int>) -> [Int] {
        var pairs: [(d2: Double, s: Int, d: Int)] = []
        for s in free {
            let pb = slots[s].kf.box
            for d in idx {
                let b = dets[d].box
                let r = b.area / max(pb.area, 1)
                guard r < 2, r > 0.5 else { continue }
                let reach = maxCentreJump * max(pb.w, pb.h, b.w, b.h)
                let d2 = (b.cx - pb.cx) * (b.cx - pb.cx) + (b.cy - pb.cy) * (b.cy - pb.cy)
                if d2 < reach * reach { pairs.append((d2, s, d)) }
            }
        }
        pairs.sort { $0.d2 < $1.d2 }
        var unmatched = Set(idx)
        for p in pairs where free.contains(p.s) && unmatched.contains(p.d) {
            free.remove(p.s); unmatched.remove(p.d)
            assign(dets[p.d], to: p.s)
        }
        return Array(unmatched)
    }

    /// Two live ids sitting on one object (the old one coasted onto the new one): keep the
    /// older id, so the rider sees one thing with a stable history.
    private func dropDuplicates() {
        var drop = Set<Int>()
        for i in slots.indices where !drop.contains(i) {
            for j in slots.indices where j > i && !drop.contains(j) {
                if slots[i].kf.box.iou(slots[j].kf.box) > 0.6 {
                    drop.insert(slots[i].id < slots[j].id ? j : i)
                }
            }
        }
        slots = slots.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
    }

    /// True when most of `a` lies inside `b`.
    static func covered(_ a: Box, by b: Box) -> Bool {
        let iw = max(0, min(a.x + a.w, b.x + b.w) - max(a.x, b.x))
        let ih = max(0, min(a.y + a.h, b.y + b.h) - max(a.y, b.y))
        return iw * ih > 0.6 * a.area
    }

    private func assign(_ det: Detection, to s: Int) {
        slots[s].kf.update(box: det.box)
        slots[s].cls = det.cls
        slots[s].hits += 1
        slots[s].misses = 0
    }

    /// Greedy best-IoU-first assignment. Returns the indices of unmatched detections.
    private func match(_ dets: [Detection], free: inout Set<Int>, minIoU: Double) -> [Int] {
        var pairs: [(iou: Double, s: Int, d: Int)] = []
        for s in free {
            let pb = slots[s].kf.box
            for (d, det) in dets.enumerated() {
                let iou = pb.iou(det.box)
                if iou >= minIoU { pairs.append((iou, s, d)) }
            }
        }
        pairs.sort { $0.iou > $1.iou }
        var unmatched = Set(dets.indices)
        for p in pairs where free.contains(p.s) && unmatched.contains(p.d) {
            free.remove(p.s); unmatched.remove(p.d)
            assign(dets[p.d], to: p.s)
        }
        return Array(unmatched)
    }
}
