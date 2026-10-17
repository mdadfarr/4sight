import Foundation

/// Per-track smoothing of range. range() switches method as a box meets or leaves the frame
/// edge, and each method answers differently, so the raw Z steps; this keeps it continuous.
public final class RangeFilter {
    private struct State { var logZ: Double; var recent: [Double]; var last: Double }

    public var tau = 0.25
    public var forgetAfter = 2.0

    private var states: [Int: State] = [:]

    public init() {}

    /// Drops one track's history (after a size jump: video cut or id swap).
    public func reset(id: Int) { states[id] = nil }

    /// Smoothed Z for this track at time t (seconds).
    public func update(id: Int, z: Double, t: Double) -> Double {
        states = states.filter { t - $0.value.last <= forgetAfter }
        // Log space: ranges err by a factor, and a factor is the same step near or far.
        let x = log(max(z, 0.01))
        guard var s = states[id] else {
            states[id] = State(logZ: x, recent: [x], last: t)
            return exp(x)
        }
        s.recent = Array((s.recent + [x]).suffix(3))
        // Median of 3 first: at 10 Hz a 0.25 s EMA alone still passes half of a one-frame spike.
        let m = s.recent.count < 3 ? x : s.recent.sorted()[1]
        s.logZ += (1 - exp(-max(t - s.last, 0) / tau)) * (m - s.logZ)
        s.last = t
        states[id] = s
        return exp(s.logZ)
    }
}
