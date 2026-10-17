// SimpleTracker.swift
//
// Gives each vehicle an id that stays the same from frame to frame, by matching
// boxes between consecutive frames by overlap (intersection over union).
// Apple's Vision framework returns boxes but no persistent ids, and
// DangerEngine needs them. A port of tracker.py.
//
// Not used by the app (Perception.Tracker supplies ids); kept as the reference port.

import Foundation

/// Corner box. Named SimpleBox so it does not clash with Perception.Box.
public struct SimpleBox: Sendable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double
    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    public var width: Double { x2 - x1 }
    public var centerX: Double { (x1 + x2) / 2 }
}

public func iou(_ a: SimpleBox, _ b: SimpleBox) -> Double {
    let iw = max(0, min(a.x2, b.x2) - max(a.x1, b.x1))
    let ih = max(0, min(a.y2, b.y2) - max(a.y1, b.y1))
    let inter = iw * ih
    let union = (a.x2 - a.x1) * (a.y2 - a.y1) + (b.x2 - b.x1) * (b.y2 - b.y1) - inter
    return union > 0 ? inter / union : 0
}

public final class SimpleTracker {
    private let iouThreshold: Double
    private let maxMissed: Int   // frames a vehicle may vanish and still keep its id
    private var tracks: [Int: (box: SimpleBox, missed: Int)] = [:]
    private var nextID = 1

    public init(iouThreshold: Double = 0.3, maxMissed: Int = 5) {
        self.iouThreshold = iouThreshold
        self.maxMissed = maxMissed
    }

    /// Takes this frame's boxes, returns one id per box (same order).
    public func update(_ boxes: [SimpleBox]) -> [Int] {
        var pairs: [(score: Double, box: Int, track: Int)] = []
        for (bi, box) in boxes.enumerated() {
            for (tid, track) in tracks {
                pairs.append((score: iou(box, track.box), box: bi, track: tid))
            }
        }
        pairs.sort { $0.score > $1.score }   // best overlaps first

        var ids = [Int?](repeating: nil, count: boxes.count)
        var used = Set<Int>()
        for p in pairs {
            if p.score < iouThreshold { break }
            if ids[p.box] == nil && !used.contains(p.track) {
                ids[p.box] = p.track
                used.insert(p.track)
            }
        }

        for tid in Array(tracks.keys) where !used.contains(tid) {   // age tracks nobody claimed
            tracks[tid]!.missed += 1
            if tracks[tid]!.missed > maxMissed { tracks[tid] = nil }
        }

        var result: [Int] = []
        for (bi, box) in boxes.enumerated() {
            let id: Int
            if let existing = ids[bi] {
                id = existing
            } else {
                id = nextID
                nextID += 1
            }
            tracks[id] = (box: box, missed: 0)
            result.append(id)
        }
        return result
    }
}
