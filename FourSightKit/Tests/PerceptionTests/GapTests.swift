import XCTest
import Protocol
@testable import Perception

final class GapTests: XCTestCase {
    let est = GapEstimator(f: 1000, u0: 640, v0: 360, cameraHeight: 1.0, imageW: 1280, imageH: 720)

    func testKnownGeometryIsUnmirrored() {
        // Box on the image right whose near (left) edge sits at u=700.
        let box = Box(x: 700, y: 300, w: 200, h: 100)
        let x = est.gap(box: box, cls: .car, z: 20)
        XCTAssertEqual(x, -(60.0 / 1000) * 24.5, accuracy: 1e-9)
        // Mirror image: box on the image left -> rider's right, positive.
        let left = Box(x: 380, y: 300, w: 200, h: 100)
        XCTAssertEqual(est.gap(box: left, cls: .car, z: 20), 1.47, accuracy: 1e-9)
    }

    func testRangeFromGroundPlaneAndFallback() {
        // bottom at v=410 -> dv=50 -> Z = 1000*1/50 = 20
        XCTAssertEqual(est.range(box: Box(x: 0, y: 310, w: 90, h: 100), cls: .car), 20, accuracy: 1e-9)
        // bottom clipped at the image edge -> width fallback 1000*1.8/90 = 20
        XCTAssertEqual(est.range(box: Box(x: 0, y: 620, w: 90, h: 100), cls: .car), 20, accuracy: 1e-9)
    }

    func testHeadingCorrection() {
        XCTAssertEqual(est.headingCorrection(deltaHeadingRad: 0.1, z: 20), 20 * tan(0.1), accuracy: 1e-12)
    }
}
