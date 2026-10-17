import Foundation
import Protocol

/// Ground-plane range and sideways gap from a box. Output is already in the rider
/// frame (un-mirrored): the rear camera's image right is the rider's left.
public struct GapEstimator: Sendable {
    public var f: Double
    public var u0: Double
    public var v0: Double
    public var cameraHeight: Double
    public var imageW: Double
    public var imageH: Double

    public init(f: Double, u0: Double, v0: Double, cameraHeight: Double = 1.0,
                imageW: Double, imageH: Double) {
        self.f = f; self.u0 = u0; self.v0 = v0; self.cameraHeight = cameraHeight
        self.imageW = imageW; self.imageH = imageH
    }

    /// Z (metres behind) from the box bottom on the ground plane, with a width fallback.
    public func range(box: Box, cls: VehicleClass) -> Double {
        let dv = box.bottom - v0
        if box.bottom < imageH - 2, dv > 0 {
            let z = f * cameraHeight / dv
            if z > 1, z < 150 { return z }
        }
        // shortcut: 1.8 m width is only right for cars; good enough for other classes at demo range.
        return f * 1.8 / max(box.w, 1)
    }

    /// Rider-frame sideways offset of the vehicle's near corner (negative = rider's left).
    public func gap(box: Box, cls: VehicleClass, z: Double) -> Double {
        let uNear = box.cx > u0 ? box.x : box.x + box.w
        let imageGap = (uNear - u0) / f * (z + cls.length)
        return -imageGap
    }

    /// Amount to subtract from the gap when the bike has yawed by delta since the box was seen.
    public func headingCorrection(deltaHeadingRad: Double, z: Double) -> Double {
        z * tan(deltaHeadingRad)
    }
}
