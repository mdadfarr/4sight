import Foundation

/// Scalar constant-velocity Kalman filter (position + velocity).
struct KF2 {
    var x: Double
    var v = 0.0
    // Covariance [[p00, p01], [p01, p11]]
    var p00 = 10.0, p01 = 0.0, p11 = 100.0
    var qPos = 1.0, qVel = 10.0, r = 4.0

    init(_ x: Double) { self.x = x }

    mutating func predict(dt: Double) {
        x += v * dt
        let np00 = p00 + dt * (2 * p01 + dt * p11) + qPos * dt
        let np01 = p01 + dt * p11
        p00 = np00; p01 = np01; p11 += qVel * dt
    }

    mutating func update(_ z: Double) {
        let s = p00 + r
        let k0 = p00 / s, k1 = p01 / s
        let y = z - x
        x += k0 * y; v += k1 * y
        let np00 = (1 - k0) * p00, np01 = (1 - k0) * p01, np11 = p11 - k1 * p01
        p00 = np00; p01 = np01; p11 = np11
    }
}

/// Constant-velocity Kalman on (cx, cy, w, h). The four axes are independent,
/// so four scalar filters are exactly equivalent to the usual 8x8 formulation.
public struct KalmanBox: Sendable {
    var cx: KF2, cy: KF2, w: KF2, h: KF2

    public init(box: Box) {
        cx = KF2(box.cx); cy = KF2(box.cy); w = KF2(box.w); h = KF2(box.h)
    }

    public mutating func predict(dt: Double) {
        cx.predict(dt: dt); cy.predict(dt: dt); w.predict(dt: dt); h.predict(dt: dt)
    }

    public mutating func update(box: Box) {
        cx.update(box.cx); cy.update(box.cy); w.update(box.w); h.update(box.h)
    }

    public var box: Box {
        let ww = max(w.x, 1), hh = max(h.x, 1)
        return Box(x: cx.x - ww / 2, y: cy.x - hh / 2, w: ww, h: hh)
    }
}
