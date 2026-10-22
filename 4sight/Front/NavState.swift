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
    /// Metres from the rider to the nearest point of the route. The countdown above is
    /// measured from that point, so far off the route it says nothing about the rider.
    var offRoute: Double = 0
    /// The fix's horizontal accuracy, metres (negative = unknown). Indoors it is often 30–100.
    var accuracy: Double = -1

    /// Further than this from the route, the banner points back to it instead of counting
    /// down to a turn measured from somewhere else.
    static let offRouteShown = 25.0
    /// Worse than this, the position (and every distance from it) is a rough guess.
    static let weakAccuracy = 30.0
    var isOffRoute: Bool { offRoute > Self.offRouteShown }
    var isWeakFix: Bool { accuracy > Self.weakAccuracy }

    var current: NavStep { steps[currentIndex] }

    /// City cycling pace including lights, about 15 km/h: the ETA holds steady at a red
    /// light instead of jumping with the speedometer.
    static let pace = 4.2

    /// Seconds to destination at a steady riding pace.
    var eta: Double { remaining / Self.pace }
}
