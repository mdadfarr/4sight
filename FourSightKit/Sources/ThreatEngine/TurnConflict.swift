import Foundation
import Protocol

/// Where the route meets traffic from behind. Navigation knows what is ahead (a turn, an
/// intersection); the rear camera knows who is coming. Neither alone sees these crashes.
///
/// Riding at the right edge (Canada), overtaking traffic comes up on the left, so:
/// - **Left turn**: the rider must cross the lane cars are using. A vehicle closing on the
///   left or straight behind means: let it pass before moving over.
/// - **Straight through an intersection**: the right hook. A car overtaking on the left as
///   the rider reaches the junction may turn right across them. Waiting does not help;
///   knowing it is there does.
/// - **Right turn**: the rider is already on the right; only a cyclist or motorbike
///   squeezing past on the right can cut in.
public enum RouteManoeuvre: Sendable, Equatable {
    case turnLeft(inMetres: Double)
    case turnRight(inMetres: Double)
    case straightThroughJunction(inMetres: Double)
}

public enum RouteConflict: Sendable, Equatable {
    /// Let it pass before moving left.
    case letPassBeforeLeft(TrackMessage)
    /// It may turn right across you at the junction.
    case rightHookAtJunction(TrackMessage)
    /// Something small is squeezing past on the right before your right turn.
    case passingOnRight(TrackMessage)

    public var track: TrackMessage {
        switch self {
        case .letPassBeforeLeft(let t), .rightHookAtJunction(let t), .passingOnRight(let t): t
        }
    }
}

public struct RouteConflictConfig: Sendable {
    /// Moving left takes a while: warn from 60 m (about 15 s at city cycling speed).
    public var leftTurnLookahead = 60.0
    /// The right hook happens at the junction itself.
    public var junctionLookahead = 35.0
    public var rightTurnLookahead = 30.0
    /// A vehicle that reaches the rider within this many seconds is in the way of a move left.
    public var leftReachSeconds = 6.0
    /// For the right hook it has to be passing the rider about as they reach the junction.
    public var junctionReachSeconds = 4.0
    /// Alongside or this close behind counts whatever it is doing, unless it is falling away.
    public var alongside = 8.0
    public var maxRange = 45.0
    /// Straight behind is as good as on the left for a move left.
    public var straightBehind = 0.5
    /// Matches ThreatConfig.closingInvTTC.
    public var closingInvTTC = 0.02
    public init() {}
}

/// The conflict to show for the manoeuvre ahead, nearest vehicle first, or nil.
/// Pure: same inputs, same answer. People on foot never count.
public func routeConflict(_ ahead: RouteManoeuvre, tracks: [TrackMessage],
                          config: RouteConflictConfig = RouteConflictConfig()) -> RouteConflict? {
    let cfg = config
    func coming(_ t: TrackMessage, within seconds: Double) -> Bool {
        guard t.cls != .person, t.z > 0, t.z <= cfg.maxRange else { return false }
        if t.z <= cfg.alongside { return t.invTTC > -cfg.closingInvTTC }
        return t.invTTC > cfg.closingInvTTC && 1 / t.invTTC <= seconds
    }
    let byRange = tracks.sorted { $0.z < $1.z }
    switch ahead {
    case .turnLeft(let m):
        guard m >= 0, m <= cfg.leftTurnLookahead else { return nil }
        return byRange.first { $0.x < cfg.straightBehind && coming($0, within: cfg.leftReachSeconds) }
            .map(RouteConflict.letPassBeforeLeft)
    case .straightThroughJunction(let m):
        guard m >= 0, m <= cfg.junctionLookahead else { return nil }
        // Cars, buses, trucks: the vehicles that turn right across a bike lane.
        return byRange.first {
            [.car, .bus, .truck].contains($0.cls) && $0.x < 0 && coming($0, within: cfg.junctionReachSeconds)
        }.map(RouteConflict.rightHookAtJunction)
    case .turnRight(let m):
        guard m >= 0, m <= cfg.rightTurnLookahead else { return nil }
        return byRange.first {
            [.bicycle, .motorcycle].contains($0.cls) && $0.x > 0.3 && coming($0, within: cfg.leftReachSeconds)
        }.map(RouteConflict.passingOnRight)
    }
}
