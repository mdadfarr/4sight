import Foundation
import Protocol
import ThreatEngine

/// Route conflicts: what is ahead on the route plus what the rear camera sees.
func runTurnChecks(_ check: (Bool, String) -> Void) {
    func tr(_ id: Int, x: Double, z: Double, invTTC: Double, cls: VehicleClass = .car) -> TrackMessage {
        TrackMessage(id: id, cls: cls, x: x, z: z, invTTC: invTTC, gapPred: abs(x), level: 0, grip: "-", turnR: false)
    }
    let closingLeft = tr(1, x: -1.5, z: 20, invTTC: 0.25)          // reaches the rider in 4 s

    // Left turn: the rider has to cross the lane cars use.
    check(routeConflict(.turnLeft(inMetres: 40), tracks: [closingLeft]) == .letPassBeforeLeft(closingLeft),
          "route: car closing on the left before a left turn -> let it pass")
    check(routeConflict(.turnLeft(inMetres: 120), tracks: [closingLeft]) == nil,
          "route: left turn still far away -> quiet")
    check(routeConflict(.turnLeft(inMetres: 40), tracks: [tr(2, x: 0.2, z: 15, invTTC: 0.3)])?.track.id == 2,
          "route: straight behind counts for a move left")
    check(routeConflict(.turnLeft(inMetres: 40), tracks: [tr(3, x: -1.5, z: 30, invTTC: 0.05)]) == nil,
          "route: car 20 s away -> quiet")
    check(routeConflict(.turnLeft(inMetres: 40), tracks: [tr(4, x: -1.2, z: 5, invTTC: -0.3)]) == nil,
          "route: alongside but falling away -> quiet")
    check(routeConflict(.turnLeft(inMetres: 40), tracks: [tr(5, x: -1.0, z: 6, invTTC: 0.4, cls: .person)]) == nil,
          "route: a pedestrian never counts")

    // Straight through a junction: the right hook.
    check(routeConflict(.straightThroughJunction(inMetres: 25), tracks: [closingLeft]) == .rightHookAtJunction(closingLeft),
          "route: car overtaking on the left at a junction -> right-hook warning")
    check(routeConflict(.straightThroughJunction(inMetres: 25), tracks: [tr(6, x: -1.5, z: 35, invTTC: 0.15)]) == nil,
          "route: car 6.7 s back passes after the junction -> quiet")
    check(routeConflict(.straightThroughJunction(inMetres: 60), tracks: [closingLeft]) == nil,
          "route: junction still far -> quiet")
    check(routeConflict(.straightThroughJunction(inMetres: 25), tracks: [tr(7, x: -1.0, z: 10, invTTC: 0.5, cls: .bicycle)]) == nil,
          "route: a cyclist passing does not right-hook")

    // Right turn: the rider is already on the right.
    check(routeConflict(.turnRight(inMetres: 20), tracks: [closingLeft]) == nil,
          "route: car on the left before a right turn -> quiet")
    check(routeConflict(.turnRight(inMetres: 20), tracks: [tr(8, x: 1.0, z: 10, invTTC: 0.4, cls: .bicycle)])?.track.id == 8,
          "route: a cyclist squeezing past on the right before a right turn -> warn")

    let nearest = routeConflict(.turnLeft(inMetres: 40), tracks: [closingLeft, tr(9, x: -1.0, z: 9, invTTC: 0.3)])
    check(nearest?.track.id == 9, "route: the nearest vehicle is the one reported")
}
