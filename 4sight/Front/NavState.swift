import Foundation

/// One manoeuvre, in the shape MKRoute.Step gives us plus a precomputed SF Symbol.
struct NavStep {
    let instruction: String
    let symbol: String
    let distance: Double   // metres, step length
    let street: String
}

struct NavState {
    var steps: [NavStep]
    var currentIndex: Int
    var distanceToManoeuvre: Double   // metres from rider to end of current step
    var remaining: Double             // metres to destination

    var current: NavStep { steps[currentIndex] }

    /// Seconds to destination at the given speed; nil when stationary.
    func eta(speed: Double) -> Double? { speed > 0.5 ? remaining / speed : nil }

    /// `--mockroute`: 5 steps, rider frozen 120 m before the end of step 2.
    static let mock: NavState = {
        let steps = [
            NavStep(instruction: "Head north", symbol: "arrow.up", distance: 350, street: "King St W"),
            NavStep(instruction: "Turn left", symbol: "arrow.turn.up.left", distance: 800, street: "Spadina Ave"),
            NavStep(instruction: "Turn right", symbol: "arrow.turn.up.right", distance: 1200, street: "Bloor St W"),
            NavStep(instruction: "Make a U-turn", symbol: "arrow.uturn.left", distance: 150, street: "Bloor St W"),
            NavStep(instruction: "Arrive", symbol: "flag.checkered", distance: 0, street: "Bathurst St"),
        ]
        let after = steps[2...].reduce(0) { $0 + $1.distance }
        return NavState(steps: steps, currentIndex: 1, distanceToManoeuvre: 120, remaining: 120 + after)
    }()
}
