import XCTest
import Protocol
@testable import Perception

final class EgoMaskTests: XCTestCase {
    /// A wheel box held still at the bottom edge for 3 s at 15 Hz, in a 1000 × 1000 frame.
    private func learn(w: Double, h: Double) -> EgoMask {
        var mask = EgoMask()
        let wheel = Detection(box: Box(x: 500 - w / 2, y: 1000 - h, w: w, h: h), cls: .person, confidence: 0.6)
        for i in 0..<45 { _ = mask.apply([wheel], imageW: 1000, imageH: 1000, t: Double(i) / 15) }
        return mask
    }

    func testSmallWheelIsMaskedWithoutWarning() {
        let mask = learn(w: 150, h: 150)
        XCTAssertEqual(mask.zones.count, 1)
        XCTAssertFalse(mask.blocksView)
    }

    func testWheelFillingTheViewWarns() {
        let mask = learn(w: 400, h: 300)   // masks 0.6 × 0.375 of the frame
        XCTAssertEqual(mask.zones.count, 1)
        XCTAssertTrue(mask.blocksView)
    }

    func testWarningSurvivesSavedZones() {
        let saved = EgoMask(zones: [.init(x1: 0.2, y1: 0.6, x2: 0.8, y2: 1.2)])   // clipped at the frame's edge
        XCTAssertEqual(saved.coverage, 0.24, accuracy: 1e-9)
        XCTAssertTrue(saved.blocksView)
    }

    func testWheelFlagIsOptionalOnTheWire() throws {
        let old = try FrameMessage.decode(line: #"{"t":1,"fps":15,"temp":"nominal","speed":0,"heading":-1,"demo":false,"tracks":[]}"#)
        XCTAssertNil(old.wheelBlocksView)
        let line = try FrameMessage(t: 1, fps: 15, temp: .nominal, speed: 0, heading: -1, demo: false,
                                    tracks: [], wheelBlocksView: true).encodeLine()
        XCTAssertTrue(String(decoding: line, as: UTF8.self).contains("\"wheel_blocks_view\":true"))
    }
}
