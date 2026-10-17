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

    /// Typical real height, metres, of what each class's box covers. YOLO's bicycle and
    /// motorcycle boxes cover the machine, not the rider, who gets a person box of his own.
    static func realHeight(_ cls: VehicleClass) -> Double? {
        switch cls {
        case .person: return 1.7
        case .bicycle: return 1.1
        case .motorcycle: return 1.2
        default: return nil
        }
    }

    /// Z (metres behind) for a box.
    ///
    /// People and two-wheelers: from apparent height, Z = f * H / h. Ground-plane range
    /// assumes the lens is level at a known height, and a handheld or bouncing phone is
    /// neither, so a tilt of a few degrees put a person 8 m away at the rider's wheel.
    /// Height needs neither. Vehicles keep the ground plane, which the replay validated.
    public func range(box: Box, cls: VehicleClass) -> Double {
        // A box cut off by the top or bottom edge is shorter than the object, so its
        // height would read too far; fall through to the ground plane / width instead.
        if let realH = Self.realHeight(cls), box.y > 2, box.bottom < imageH - 2, box.h > 4 {
            return f * realH / box.h
        }
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
