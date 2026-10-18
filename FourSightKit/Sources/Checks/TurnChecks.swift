import Foundation
import Protocol
import ThreatEngine

/// Right-hook warning: the turn ahead plus what the rear camera sees on that side.
func runTurnChecks(_ check: (Bool, String) -> Void) {
    func tr(_ id: Int, x: Double, z: Double, invTTC: Double, cls: VehicleClass = .car) -> TrackMessage {
        TrackMessage(id: id, cls: cls, x: x, z: z, invTTC: invTTC, gapPred: abs(x), level: 0, grip: "-", turnR: false)
    }
    let closingRight = tr(1, x: 1.5, z: 20, invTTC: 0.25)          // reaches the rider in 4 s

    check(turnConflict(turn: .right, metresToTurn: 40, tracks: [closingRight])?.id == 1,
          "turn: car closing on the right before a right turn -> warn")
    check(turnConflict(turn: .right, metresToTurn: 120, tracks: [closingRight]) == nil,
          "turn: turn still far away -> quiet")
    check(turnConflict(turn: .left, metresToTurn: 40, tracks: [closingRight]) == nil,
          "turn: car on the right does not block a left turn")
    check(turnConflict(turn: .right, metresToTurn: 40, tracks: [tr(2, x: 1.5, z: 30, invTTC: 0.05)]) == nil,
          "turn: car 20 s away -> quiet")
    check(turnConflict(turn: .right, metresToTurn: 40, tracks: [tr(3, x: 0.2, z: 15, invTTC: 0.3)])?.id == 3,
          "turn: straight behind and closing counts")
    check(turnConflict(turn: .right, metresToTurn: 40, tracks: [tr(4, x: 1.2, z: 5, invTTC: 0)])?.id == 4,
          "turn: alongside on the right, not closing, still blocks")
    check(turnConflict(turn: .right, metresToTurn: 40, tracks: [tr(5, x: 1.2, z: 5, invTTC: -0.3)]) == nil,
          "turn: alongside but falling away -> quiet")
    check(turnConflict(turn: .right, metresToTurn: 40, tracks: [tr(6, x: 1.0, z: 6, invTTC: 0.4, cls: .person)]) == nil,
          "turn: a pedestrian never counts")
    check(turnConflict(turn: .right, metresToTurn: 40, tracks: [tr(7, x: 1.0, z: 12, invTTC: 0.4, cls: .bicycle)])?.id == 7,
          "turn: a cyclist passing on the right counts")
    let near = turnConflict(turn: .right, metresToTurn: 40,
                            tracks: [closingRight, tr(8, x: 1.0, z: 9, invTTC: 0.3)])
    check(near?.id == 8, "turn: the nearest conflicting vehicle is reported")
    check(turnConflict(turn: .left, metresToTurn: 30, tracks: [tr(9, x: -1.4, z: 18, invTTC: 0.3)])?.id == 9,
          "turn: mirror case, car on the left before a left turn")
}
