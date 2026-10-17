import XCTest
@testable import Perception

final class RideSidecarTests: XCTestCase {
    let cameraJSON = """
    {"f": 1200.5, "u0": 640.0, "v0": 360.0, "width": 1280, "height": 720,
     "camera_height": 1.4, "frames": 600, "fps": 20.0, "duration": 30.0, "source": "bag.mcap"}
    """

    func testCameraJSONIgnoresExtraKeys() throws {
        let cam = try XCTUnwrap(RideCamera(json: Data(cameraJSON.utf8)))
        XCTAssertEqual(cam.f, 1200.5)
        XCTAssertEqual(cam.width, 1280)
        XCTAssertEqual(cam.cameraHeight, 1.4)
        XCTAssertEqual(cam.fps, 20)
    }

    func testCameraJSONWithoutIntrinsicsIsNil() {
        // What the tool writes when the bag window held no camera_info message.
        XCTAssertNil(RideCamera(json: Data(#"{"frames": 10, "fps": 20.0}"#.utf8)))
    }

    func testCameraScalesToADifferentClipSize() {
        let cam = RideCamera(f: 1000, u0: 640, v0: 360, width: 1280, height: 720, cameraHeight: 1.4)
        let half = cam.scaled(toWidth: 640, height: 360)
        XCTAssertEqual(half.f, 500)
        XCTAssertEqual(half.u0, 320)
        XCTAssertEqual(half.v0, 180)
        XCTAssertEqual(half.cameraHeight, 1.4)   // metres, not pixels
    }

    func testTrackRebasesToItsFirstFixAndSkipsJunk() throws {
        // Line 2 is the kind of truncated line a killed logger leaves behind.
        let jsonl = """
        {"t":104.0,"lat":43.77,"lon":-79.25,"speed":4.0,"heading":182.0}
        {"t":105.0,"lat":43.77,"lon":
        {"t":106.0,"lat":43.78,"lon":-79.26,"speed":6.0,"heading":184.0}

        {"t":108.0,"lat":43.79,"lon":-79.27,"speed":8.0,"heading":186.0}
        """
        let track = try XCTUnwrap(RideTrack(jsonl: jsonl))
        XCTAssertEqual(track.fixes.count, 3)
        XCTAssertEqual(track.startT, 104.0)
        XCTAssertEqual(track.fixes.map(\.t), [0, 2, 4])
        XCTAssertEqual(track.duration, 4)
    }

    func testFixLookupHoldsTheLastFixUntilTheNextOne() throws {
        let track = try XCTUnwrap(RideTrack(fixes: [
            RideFix(t: 10, lat: 0, lon: 0, speed: 4, heading: 10),
            RideFix(t: 11, lat: 0, lon: 0, speed: 6, heading: 20),
            RideFix(t: 13, lat: 0, lon: 0, speed: 8, heading: 30),
        ]))
        XCTAssertEqual(track.fix(at: -5)?.speed, 4)      // before the log starts
        XCTAssertEqual(track.fix(at: 0)?.speed, 4)
        XCTAssertEqual(track.fix(at: 0.9)?.speed, 4)
        XCTAssertEqual(track.fix(at: 1)?.speed, 6)
        XCTAssertEqual(track.fix(at: 2.5)?.speed, 6)     // the 1 Hz gap holds 6
        XCTAssertEqual(track.fix(at: 3)?.speed, 8)
        XCTAssertEqual(track.fix(at: 999)?.speed, 8)     // past the end
    }

    func testUnsortedAndEmptyInput() throws {
        let track = try XCTUnwrap(RideTrack(fixes: [
            RideFix(t: 5, lat: 0, lon: 0, speed: 9),
            RideFix(t: 1, lat: 0, lon: 0, speed: 3),
        ]))
        XCTAssertEqual(track.fixes.map(\.speed), [3, 9])
        XCTAssertNil(RideTrack(fixes: []))
        XCTAssertNil(RideTrack(jsonl: "\n\nnot json\n"))
    }

    func testMissingSpeedAndHeadingFallBackToTheContractDefaults() throws {
        let track = try XCTUnwrap(RideTrack(jsonl: #"{"t":0,"lat":43.0,"lon":-79.0}"#))
        XCTAssertEqual(track.fixes[0].speed, 0)
        XCTAssertEqual(track.fixes[0].heading, -1)
    }

    func testSidecarFoundNextToTheClip() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ride-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let clip = dir.appendingPathComponent("ride-bag.mp4")
        try Data().write(to: clip)
        try Data(cameraJSON.utf8).write(to: dir.appendingPathComponent("ride-bag.camera.json"))
        try #"{"t":7.0,"lat":43.0,"lon":-79.0,"speed":5.0,"heading":90.0}"#
            .write(to: dir.appendingPathComponent("ride-bag.jsonl"), atomically: true, encoding: .utf8)

        let ride = RideSidecar(videoURL: clip)
        XCTAssertEqual(ride.camera?.f, 1200.5)
        XCTAssertEqual(ride.track?.fix(at: 0)?.speed, 5)
        // A clip on its own (what RideLogger-only or hand-dropped footage looks like).
        XCTAssertNil(RideSidecar(videoURL: dir.appendingPathComponent("absent.mp4")).camera)
        XCTAssertNil(RideSidecar(videoURL: dir.appendingPathComponent("absent.mp4")).track)
    }
}
