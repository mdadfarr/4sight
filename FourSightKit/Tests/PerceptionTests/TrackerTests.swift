import XCTest
import Protocol
@testable import Perception

final class TrackerTests: XCTestCase {
    func testMovingBoxKeepsOneID() {
        let tr = Tracker()
        var ids = Set<Int>()
        for i in 0..<20 {
            let d = Detection(box: Box(x: 100 + Double(i) * 8, y: 200, w: 120, h: 90), cls: .car, confidence: 0.8)
            let out = tr.update(detections: [d], dt: 1 / 30)
            if i >= 1 {
                XCTAssertEqual(out.count, 1, "frame \(i)")
                ids.formUnion(out.map(\.id))
            }
        }
        XCTAssertEqual(ids.count, 1)
    }

    func testTwoBoxesKeepDistinctIDs() {
        let tr = Tracker()
        var pairs = Set<[Int]>()
        for i in 0..<20 {
            let a = Detection(box: Box(x: 100 + Double(i) * 5, y: 200, w: 100, h: 80), cls: .car, confidence: 0.9)
            let b = Detection(box: Box(x: 700 - Double(i) * 5, y: 300, w: 140, h: 100), cls: .truck, confidence: 0.6)
            let out = tr.update(detections: [a, b], dt: 1 / 30)
            if i >= 1 {
                XCTAssertEqual(out.count, 2)
                pairs.insert(out.sorted { $0.box.x < $1.box.x }.map(\.id))
            }
        }
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(Set(pairs.first!).count, 2)
    }

    func testLowConfidenceKeepsTrackAliveButDoesNotSpawn() {
        let tr = Tracker()
        let box = Box(x: 100, y: 100, w: 100, h: 100)
        XCTAssertTrue(tr.update(detections: [Detection(box: box, cls: .car, confidence: 0.3)], dt: 0.03).isEmpty)
        _ = tr.update(detections: [Detection(box: box, cls: .car, confidence: 0.3)], dt: 0.03)
        XCTAssertTrue(tr.update(detections: [], dt: 0.03).isEmpty)
    }
}
