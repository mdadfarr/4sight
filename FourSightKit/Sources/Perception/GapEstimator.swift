import Foundation
import Protocol

/// Range and sideways gap from a box. Output is already in the rider
/// frame (un-mirrored): the rear camera's image right is the rider's left.
public struct GapEstimator: Sendable {
    public var f: Double
    public var u0: Double
    public var v0: Double
    public var cameraHeight: Double
    public var imageW: Double
    public var imageH: Double
    /// Where the lens sits right of the bike's centreline, metres (negative = left). The
    /// rear phone is not mounted dead centre, so "straight behind the camera" is this far
    /// to the rider's right.
    public var cameraOffset = 0.0

    public init(f: Double, u0: Double, v0: Double, cameraHeight: Double = 1.0,
                imageW: Double, imageH: Double) {
        self.f = f; self.u0 = u0; self.v0 = v0; self.cameraHeight = cameraHeight
        self.imageW = imageW; self.imageH = imageH
    }

    /// Typical real size, metres, seen from behind or in front (the camera looks back along
    /// the road). YOLO's bicycle and motorcycle boxes cover the machine, not the rider, who
    /// gets a person box of his own.
    static func realSize(_ cls: VehicleClass) -> (h: Double, w: Double) {
        switch cls {
        case .person: return (1.7, 0.5)
        case .bicycle: return (1.1, 0.6)
        case .motorcycle: return (1.2, 0.8)
        case .car: return (1.5, 1.8)
        case .bus: return (3.2, 2.5)
        case .truck: return (3.0, 2.5)
        }
    }

    /// Z (metres behind) for a box.
    ///
    /// Cars, buses, trucks: ground plane from the box bottom, which the replay validated.
    /// Everything else, and vehicles whose bottom is cut off: Z = f * H / h, or f * W / w when
    /// the top or bottom is cut off. Ground-plane range assumes a level lens at a known height;
    /// a handheld or bouncing phone is neither, so a tilt of a few degrees put a person 8 m
    /// away at the rider's wheel. Height and width need neither.
    public func range(box: Box, cls: VehicleClass) -> Double {
        if [.car, .bus, .truck].contains(cls), box.bottom < imageH - 2, box.bottom > v0 {
            let z = f * cameraHeight / (box.bottom - v0)
            if z > 1, z < 150 { return z }
        }
        let size = Self.realSize(cls)
        let fromH = f * size.h / max(box.h, 1), fromW = f * size.w / max(box.w, 1)
        if box.y > 2, box.bottom < imageH - 2 { return fromH }
        if box.x > 2, box.x + box.w < imageW - 2 { return fromW }
        // Cut off both ways, so very close. A truncated box is too small, which makes each
        // estimate an upper bound: take the tighter one.
        return max(0.5, min(fromH, fromW))
    }

    /// Rider-frame sideways offset of the vehicle's near corner (negative = rider's left).
    public func gap(box: Box, cls: VehicleClass, z: Double) -> Double {
        let uNear = box.cx > u0 ? box.x : box.x + box.w
        let imageGap = (uNear - u0) / f * (z + cls.length)
        return -imageGap + cameraOffset
    }

    /// Amount to subtract from the gap when the bike has yawed by delta since the box was seen.
    public func headingCorrection(deltaHeadingRad: Double, z: Double) -> Double {
        z * tan(deltaHeadingRad)
    }
}
