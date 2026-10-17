import XCTest
@testable import Perception

final class TTCTests: XCTestCase {
    func testAreaGrowthYieldsInverseTTC() {
        let est = TTCEstimator()
        let T = 10.0
        var t = 0.0
        var result: Double?
        while t < 4.0 {
            let side = 100 / (T - t)   // area ∝ 1/(T-t)²
            result = est.update(id: 1, box: Box(x: 0, y: 0, w: side, h: side), t: t, touchesEdge: false)
            t += 1 / 30
        }
        let truth = 1 / (T - (t - 1 / 30))
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, truth, accuracy: truth * 0.15)
    }

    func testNeedsHistoryAndFreezesAtEdge() {
        let est = TTCEstimator()
        XCTAssertNil(est.update(id: 1, box: Box(x: 0, y: 0, w: 10, h: 10), t: 0, touchesEdge: false))
        XCTAssertNil(est.update(id: 1, box: Box(x: 0, y: 0, w: 11, h: 11), t: 0.1, touchesEdge: false))
        let v = est.update(id: 1, box: Box(x: 0, y: 0, w: 12, h: 12), t: 0.4, touchesEdge: false)
        XCTAssertNotNil(v)
        XCTAssertEqual(est.update(id: 1, box: Box(x: 0, y: 0, w: 50, h: 50), t: 0.5, touchesEdge: true), v)
    }
}
