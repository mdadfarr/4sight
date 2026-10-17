import XCTest
@testable import Protocol

final class ProtocolTests: XCTestCase {
    let example = """
    {"t":1712.43,"fps":24,"temp":"nominal","speed":5.3,"heading":182.0,"demo":false,
     "tracks":[{"id":7,"cls":"car","x":-1.4,"z":18.2,"inv_ttc":0.21,
                "gap_pred":0.8,"level":2,"grip":"L","turn_r":false}]}
    """

    func testRoundTrip() throws {
        let msg = try FrameMessage.decode(line: example)
        XCTAssertEqual(msg.t, 1712.43)
        XCTAssertEqual(msg.fps, 24)
        XCTAssertEqual(msg.temp, .nominal)
        XCTAssertEqual(msg.tracks.count, 1)
        XCTAssertEqual(msg.tracks[0].cls, .car)
        XCTAssertEqual(msg.tracks[0].invTTC, 0.21)
        XCTAssertEqual(msg.tracks[0].gapPred, 0.8)
        XCTAssertEqual(msg.tracks[0].grip, "L")
        XCTAssertFalse(msg.tracks[0].turnR)

        let line = try msg.encodeLine()
        XCTAssertEqual(line.last, 0x0A)
        let text = String(decoding: line, as: UTF8.self)
        for key in ["\"inv_ttc\"", "\"gap_pred\"", "\"turn_r\"", "\"temp\"", "\"demo\""] {
            XCTAssertTrue(text.contains(key), "missing \(key)")
        }
        XCTAssertEqual(try FrameMessage.decode(line: line), msg)
    }

    func testBLECommands() {
        XCTAssertEqual(BLECommand.left(level: 1).ascii, "L1")
        XCTAssertEqual(BLECommand.left(level: 3).ascii, "L3")
        XCTAssertEqual(BLECommand.right(level: 2).ascii, "R2")
        XCTAssertEqual(BLECommand.clear.ascii, "X")
        XCTAssertEqual(BLECommand.heartbeat.ascii, "H")
        XCTAssertEqual(BLECommand.right(level: 9).ascii, "R3")
        XCTAssertEqual(BLECommand.left(level: 2).data, Data("L2".utf8))
        XCTAssertEqual(BLECommand.from(grip: "L", level: 2), .left(level: 2))
        XCTAssertNil(BLECommand.from(grip: "-", level: 2))
        XCTAssertEqual(BLEIDs.service, "5db17fa8-6860-4cd4-bd95-50e90510e072")
        XCTAssertEqual(BLEIDs.command, "2490e4c3-b5b8-40db-8ab6-8cc856e1fa31")
    }
}
