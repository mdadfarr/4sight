import CoreGraphics
import Foundation

/// The canvas `docs/mock/front.html` is drawn at. Everything is laid out in these
/// points and scaled once onto the real screen, so every constant ported from the
/// mock stays literally the same number.
enum Design {
    static let width: Double = 393
    static let height: Double = 852
    static let bannerH: Double = 190
}

struct Projected {
    let x, y, s: Double
    var cg: CGPoint { CGPoint(x: x, y: y) }
}

/// A pinhole camera following the rider: 26 m up, 8 m behind, tilted 20° forward.
///
/// Pinned by two screen positions rather than a raw focal length: the rider sits at
/// y = 430 and the road 20 m behind lands at y = 752. Height and tilt then decide how
/// much of the way ahead fits above the rider and how much the rear is magnified.
/// One projection for everything; separate x and y curves shear the world.
enum Camera {
    static let height = 26.0
    static let behind = 8.0
    static let tilt = -20.0 * .pi / 180

    private static let riderY = 430.0
    private static let rearY = 752.0
    private static let rearZ = 20.0

    private static func u(_ z: Double) -> Double { tan(-tilt + atan((z - behind) / height)) }

    static let f = (rearY - riderY) / (u(rearZ) - u(0))
    static let cx = Design.width / 2
    static let cy = riderY - f * u(0)

    private static let sinT = sin(tilt)
    private static let cosT = cos(tilt)

    /// Rider frame to screen. x metres right, z metres behind, h metres up.
    static func pt(_ x: Double, _ z: Double, _ h: Double = 0) -> Projected {
        let dz = z - behind, dy = h - height
        let depth = -dy * cosT + dz * sinT
        let up = -dy * sinT - dz * cosT
        return Projected(x: cx + f * x / depth, y: cy - f * up / depth, s: f / depth)
    }

    /// Screen points per metre at range z: grows toward the camera, shrinks ahead.
    static func ppm(_ z: Double) -> Double { pt(0, z).s }

    /// The four corners of a w by l rectangle centred at (x, z), h metres up.
    static func slab(_ x: Double, _ z: Double, _ w: Double, _ l: Double, _ h: Double = 0) -> [Projected] {
        [pt(x - w / 2, z - l / 2, h), pt(x + w / 2, z - l / 2, h),
         pt(x + w / 2, z + l / 2, h), pt(x - w / 2, z + l / 2, h)]
    }
}

/// What the rear camera can see, from CONTRACTS.md: ±35°, 0 to 40 m behind.
/// Nothing detected is ever drawn outside this wedge.
enum FOV {
    static let half = 35.0 * .pi / 180
    static let zMax = 40.0
    static let zMin = 0.6

    static func coneHalfWidth(_ z: Double) -> Double { z * tan(half) }

    static func seen(_ x: Double, _ z: Double, margin: Double = 0) -> Bool {
        guard z >= zMin, z <= zMax else { return false }
        return abs(x) <= coneHalfWidth(z) + margin
    }
}
