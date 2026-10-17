// SimpleTrackerTests.swift — port of ml/test_tracker.py (6 cases).

import XCTest
@testable import ThreatEngine

final class SimpleTrackerTests: XCTestCase {
    func car(_ cx: Double, _ half: Double) -> SimpleBox {
        SimpleBox(x1: cx - half, y1: 100, x2: cx + half, y2: 100 + half)
    }

    func testIouBasics() {
        XCTAssertEqual(iou(SimpleBox(x1: 0, y1: 0, x2: 10, y2: 10), SimpleBox(x1: 0, y1: 0, x2: 10, y2: 10)), 1.0, accuracy: 1e-9)
        XCTAssertEqual(iou(SimpleBox(x1: 0, y1: 0, x2: 10, y2: 10), SimpleBox(x1: 20, y1: 20, x2: 30, y2: 30)), 0.0, accuracy: 1e-9)
        XCTAssertEqual(iou(SimpleBox(x1: 0, y1: 0, x2: 10, y2: 10), SimpleBox(x1: 5, y1: 0, x2: 15, y2: 10)), 1.0 / 3.0, accuracy: 1e-9)
    }

    func testAGrowingCarKeepsItsID() {
        let tr = SimpleTracker()
        var ids = Set<Int>()
        for i in 0..<10 {
            ids.insert(tr.update([car(300, 30 + 4 * Double(i))])[0])
        }
        XCTAssertEqual(ids.count, 1)
    }

    func testTwoCarsKeepSeparateIDs() {
        let tr = SimpleTracker()
        let first = tr.update([car(100, 30), car(500, 30)])
        var ids = first
        for i in 1..<6 {
            let d = Double(i)
            ids = tr.update([car(100 + 2 * d, 30 + d), car(500 - 2 * d, 30 + d)])
        }
        XCTAssertEqual(ids, first)
        XCTAssertNotEqual(first[0], first[1])
    }

    func testANewCarGetsANewID() {
        let tr = SimpleTracker()
        let a = tr.update([car(100, 30)])[0]
        let ids = tr.update([car(102, 31), car(500, 30)])
        XCTAssertEqual(ids[0], a)
        XCTAssertNotEqual(ids[1], a)
    }

    func testACarCanVanishBrieflyAndKeepItsID() {
        let tr = SimpleTracker(maxMissed: 5)
        let a = tr.update([car(300, 40)])[0]
        for _ in 0..<3 { _ = tr.update([]) }
        XCTAssertEqual(tr.update([car(302, 41)])[0], a)
    }

    func testACarGoneTooLongGetsANewID() {
        let tr = SimpleTracker(maxMissed: 5)
        let a = tr.update([car(300, 40)])[0]
        for _ in 0..<7 { _ = tr.update([]) }
        XCTAssertNotEqual(tr.update([car(302, 41)])[0], a)
    }
}
