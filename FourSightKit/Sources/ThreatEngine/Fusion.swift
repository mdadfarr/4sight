import Foundation

/// What DangerEngine says about one track this frame. Range-free: it comes from how fast
/// the box widens and where it sits in the image, not from any distance estimate.
public struct DangerVote: Equatable, Sendable {
    public var level: AlertLevel
    public var side: Side
    public init(level: AlertLevel, side: Side) { self.level = level; self.side = side }
}

/// One decision from two engines that fail differently.
///
/// ThreatEngine is the backbone: metric, lane-aware, interpretable, but only as good as
/// its range estimate (a class-size prior can be 2x off for an occluded person or a box
/// cut by the frame edge). DangerEngine needs no range, only box growth, but alone it
/// cried wolf (~198 s of false urgents on Arshiya's footage). So Danger never alerts on
/// its own; it can only confirm, sharpen or rescue what ThreatEngine already sees:
///
/// 1. Confirm: a track Danger rates warning or worse needs `corroboratedDebounceFrames`
///    instead of `debounceFrames` (see `corroborated`, passed into ThreatEngine.update).
/// 2. Sharpen: Threat at 2 and Danger urgent → 3 (imminent).
/// 3. Rescue: Threat at 1 (closing, inside the caution band) and Danger urgent → 2.
///    Danger's urgent already carries ≥5 frames of growth evidence, so no extra debounce.
/// Threat at 0 stays 0 whatever Danger says: metric says it passes wide or is not closing.
public enum Fusion {
    /// Tracks Danger rates warning (TTC < 3 s) or worse.
    public static func corroborated(_ votes: [Int: DangerVote]) -> Set<Int> {
        Set(votes.filter { $0.value.level >= .warning }.map(\.key))
    }

    /// ThreatEngine's decisions adjusted by Danger's votes. `states` supply the sideways
    /// gap for the grip of a rescued track, which ThreatEngine left on "-".
    public static func fuse(_ threat: [Decision], votes: [Int: DangerVote],
                            states: [TrackState]) -> [Decision] {
        let gaps = Dictionary(states.map { ($0.id, $0.gap) }, uniquingKeysWith: { a, _ in a })
        return threat.map { d in
            guard let vote = votes[d.id], vote.level == .urgent else { return d }
            var out = d
            if d.level == 2 {
                out.level = 3
            } else if d.level == 1 {
                out.level = 2
                out.grip = grip(gap: gaps[d.id], side: vote.side)
            }
            return out
        }
    }

    /// Side from the metric gap when it is clearly off-centre, else Danger's image side;
    /// dead behind goes to the left grip, the side cars pass on.
    static func grip(gap: Double?, side: Side) -> String {
        if let gap, abs(gap) > 0.3 { return gap > 0 ? "R" : "L" }
        return side == .right ? "R" : "L"
    }
}
