import Foundation
import Protocol

/// The right hook, and its mirror on a left turn: the rider is about to turn, and a
/// vehicle behind on that side will reach them first. Navigation knows the turn and the
/// rear camera knows the vehicle; neither alone can see this crash coming.
public enum TurnSide: Sendable { case left, right }

public struct TurnConflictConfig: Sendable {
    /// Warn from this far before the turn: about 15 s at city cycling speed.
    public var lookahead = 60.0
    /// A vehicle that reaches the rider within this many seconds is in the way.
    public var reachSeconds = 6.0
    /// Alongside or this close behind on the turning side counts whatever it is doing.
    public var alongside = 8.0
    public var maxRange = 45.0
    /// Straight behind is in the way too: a vehicle up to this far toward the other side counts.
    public var straightBehind = 0.5
    /// Matches ThreatConfig.closingInvTTC.
    public var closingInvTTC = 0.02
    public init() {}
}

/// The nearest vehicle that conflicts with turning to `turn` in `metresToTurn`, or nil.
/// Pure: same inputs, same answer. People on foot never count; a cyclist passing on the
/// turning side does.
public func turnConflict(turn: TurnSide, metresToTurn: Double, tracks: [TrackMessage],
                         config: TurnConflictConfig = TurnConflictConfig()) -> TrackMessage? {
    let cfg = config
    guard metresToTurn >= 0, metresToTurn <= cfg.lookahead else { return nil }
    let sign = turn == .right ? 1.0 : -1.0          // rider frame: x > 0 is the rider's right
    return tracks
        .filter { t in
            guard t.cls != .person, t.z > 0, t.z <= cfg.maxRange, t.x * sign > -cfg.straightBehind else { return false }
            if t.z <= cfg.alongside { return t.invTTC > -cfg.closingInvTTC }   // here, not falling away
            return t.invTTC > cfg.closingInvTTC && 1 / t.invTTC <= cfg.reachSeconds
        }
        .min { $0.z < $1.z }
}
