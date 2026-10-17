import Foundation

/// Inverse time-to-contact from box area growth: area ∝ 1/Z², so d(ln A)/dt = 2/TTC.
public final class TTCEstimator {
    private struct History {
        var samples: [(t: Double, lnA: Double)] = []
        var slope: Double?
        var last: Double
    }

    public var window = 1.0
    public var minHistory = 0.3
    public var smoothing = 0.3
    public var forgetAfter = 2.0

    private var hist: [Int: History] = [:]

    public init() {}

    /// Drops one track's history (after a size jump: video cut or id swap).
    public func reset(id: Int) { hist[id] = nil }

    /// Returns invTTC (1/s) or nil until enough history exists. Freezes while the box
    /// touches the frame edge because a clipped box no longer measures the vehicle.
    public func update(id: Int, box: Box, t: Double, touchesEdge: Bool) -> Double? {
        hist = hist.filter { t - $0.value.last <= forgetAfter }
        var h = hist[id] ?? History(last: t)
        h.last = t
        defer { hist[id] = h }
        guard !touchesEdge, box.area > 0 else { return h.slope.map { $0 / 2 } }

        h.samples.append((t, log(box.area)))
        h.samples.removeAll { t - $0.t > window }
        guard let first = h.samples.first, t - first.t >= minHistory else { return nil }

        let n = Double(h.samples.count)
        let mt = h.samples.reduce(0) { $0 + $1.t } / n
        let ma = h.samples.reduce(0) { $0 + $1.lnA } / n
        var num = 0.0, den = 0.0
        for s in h.samples {
            num += (s.t - mt) * (s.lnA - ma)
            den += (s.t - mt) * (s.t - mt)
        }
        guard den > 0 else { return nil }
        let raw = num / den
        h.slope = h.slope.map { $0 + smoothing * (raw - $0) } ?? raw
        return h.slope! / 2
    }
}
