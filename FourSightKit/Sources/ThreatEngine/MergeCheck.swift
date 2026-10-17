import Foundation
import Protocol

/// Which lane the rider is asking about. Rider frame: left is negative `gap`.
public enum MergeSide: String, Equatable, Sendable {
    case left = "L"
    case right = "R"

    /// Sign of the `gap` values that lie in this lane.
    var sign: Double { self == .left ? -1 : 1 }
}

/// The answer to one press of a handlebar button.
public struct MergeVerdict: Equatable, Sendable {
    public var side: MergeSide
    public var clear: Bool
    /// The track that blocked it, for the front UI and the log. nil when clear.
    public var blockedBy: Int?
    /// Short human-readable cause, for logs and the rear screen.
    public var reason: String

    public init(side: MergeSide, clear: Bool, blockedBy: Int? = nil, reason: String) {
        self.side = side; self.clear = clear; self.blockedBy = blockedBy; self.reason = reason
    }
}

public struct MergeConfig: Sendable {
    /// Anything this close behind or alongside blocks, closing or not: the rider would
    /// swing into the space it already occupies.
    public var alongsideZ = 8.0
    /// A vehicle further back blocks if it would reach the rider within this many seconds.
    public var reachSeconds = 5.0
    /// Treated as closing above this 1/TTC, matching ThreatConfig.closingInvTTC.
    public var closingInvTTC = 0.02
    /// How far out from the rider the target lane extends. One lane is ~3.3 m; the far
    /// edge is generous because a gap estimate that large is noise anyway.
    public var laneFar = 5.5
    /// How far the lane reaches back across the centreline. A vehicle straddling the line
    /// or sitting directly behind the rider still blocks the move.
    public var laneNear = 0.75
    /// A track seen for fewer frames than this is not trusted to clear a lane.
    public var minFrames = 2
    /// Tracks older than this (no frame carrying them) make the whole answer untrustworthy.
    public var staleAfter = 0.75
    public init() {}
}

/// Decides whether the rider may move into the lane on `side`.
///
/// Pure: same inputs, same answer, no clock and no state. The caller supplies `age`,
/// the seconds since the frame these tracks came from.
///
/// Safety rule, and the reason this is not just a filter: **every uncertainty answers
/// blocked.** Stale tracks, too-few frames, a gap we cannot estimate. Green here means
/// a rider pulls into a live traffic lane without looking, so green must be earned.
public func mergeCheck(side: MergeSide, tracks: [TrackState], age: TimeInterval = 0,
                       config: MergeConfig = MergeConfig()) -> MergeVerdict {
    let cfg = config

    // The rider pressed the button now; tracks from a stalled pipeline cannot answer.
    guard age <= cfg.staleAfter else {
        return MergeVerdict(side: side, clear: false, reason: "no fresh view")
    }

    for t in tracks {
        // Is it in the lane we are asking about? `gap` is signed, negative = rider's left,
        // so flipping by the side's sign puts "into that lane" in the positive direction.
        let lateral = t.gap * side.sign
        guard lateral > -cfg.laneNear, lateral < cfg.laneFar else { continue }

        // A brand-new track has a meaningless velocity; treat it as a blocker rather
        // than waiting for it to firm up.
        if t.framesSeen < cfg.minFrames {
            return MergeVerdict(side: side, clear: false, blockedBy: t.id,
                                reason: "unconfirmed \(t.cls.rawValue)")
        }
        // Alongside or close behind: the space is taken, whatever it is doing.
        if t.z <= cfg.alongsideZ {
            return MergeVerdict(side: side, clear: false, blockedBy: t.id,
                                reason: "\(t.cls.rawValue) alongside")
        }
        // Further back but closing fast enough to arrive during the move.
        if t.invTTC > cfg.closingInvTTC, 1 / t.invTTC <= cfg.reachSeconds {
            return MergeVerdict(side: side, clear: false, blockedBy: t.id,
                                reason: "\(t.cls.rawValue) closing")
        }
    }
    return MergeVerdict(side: side, clear: true, reason: "lane clear")
}
