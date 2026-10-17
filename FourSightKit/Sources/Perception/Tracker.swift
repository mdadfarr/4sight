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

        for i in free {
            slots[i].misses += 1
        }
        slots.removeAll { $0.misses > maxMisses }

        unmatchedHigh.sort()
        for d in unmatchedHigh.map({ high[$0] }) {
            slots.append(Slot(id: nextID, cls: d.cls, kf: KalmanBox(box: d.box)))
            nextID += 1
        }

        return slots.filter { $0.hits >= minHits }.map {
            Track(id: $0.id, cls: $0.cls, box: $0.kf.box, hits: $0.hits, misses: $0.misses, age: $0.age)
        }
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
            slots[p.s].kf.update(box: dets[p.d].box)
            slots[p.s].cls = dets[p.d].cls
            slots[p.s].hits += 1
            slots[p.s].misses = 0
        }
        return Array(unmatched)
    }
}
