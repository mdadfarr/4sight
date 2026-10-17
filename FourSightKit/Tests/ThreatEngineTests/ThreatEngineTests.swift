import XCTest
import Protocol
@testable import ThreatEngine

final class ThreatEngineTests: XCTestCase {
    /// Runs the same track for n frames at 20 Hz and returns the last decision.
    func run(_ engine: ThreatEngine, _ t: TrackState, frames: Int, speed: Double = 5, demo: Bool = false,
             from start: Double = 0) -> Decision? {
        var last: Decision?
        for i in 0..<frames {
            last = engine.update(tracks: [t], bikeSpeed: speed, demoMode: demo,
                                 now: start + Double(i) * 0.05).first
        }
        return last
    }

    // z=20, invTTC=0.2 -> TTC 5 s, aReq = 20/50 = 0.4 (not imminent).
    func car(gap: Double, cls: VehicleClass = .car, turnR: Bool = false) -> TrackState {
        TrackState(id: 1, cls: cls, z: 20, gap: gap, invTTC: 0.2, turnR: turnR)
    }

    func testClosingCarInsideThresholdIsThreatAfterDebounce() {
        let e = ThreatEngine()
        let t = car(gap: -0.8)
        XCTAssertEqual(run(e, t, frames: 3)?.level, 1)
        let d = run(e, t, frames: 1, from: 1)
        XCTAssertEqual(d?.level, 2)
        XCTAssertEqual(d?.grip, "L")
        XCTAssertEqual(d!.gapPred, 0.8, accuracy: 1e-9)
    }

    func testCautionBandIsLevelOneOnly() {
        let e = ThreatEngine()
        XCTAssertEqual(run(e, car(gap: -1.2), frames: 10)?.level, 1)
        XCTAssertEqual(run(ThreatEngine(), car(gap: -2.0), frames: 10)?.level, 0)
    }

    func testBusUsesLargerThreshold() {
        let d = run(ThreatEngine(), car(gap: -1.3, cls: .bus), frames: 4)
        XCTAssertEqual(d?.level, 2)
        XCTAssertEqual(run(ThreatEngine(), car(gap: -1.3), frames: 4)?.level, 1)
    }

    func testImminentWhenRequiredDecelHigh() {
        // z=10, invTTC=1 -> TTC 1 s, aReq = 10/2 = 5 >= 3.
        let t = TrackState(id: 1, cls: .car, z: 10, gap: -0.5, invTTC: 1)
        XCTAssertEqual(run(ThreatEngine(), t, frames: 4)?.level, 3)
    }

    func testParkedCarIsSilent() {
        let t = TrackState(id: 1, cls: .car, z: 10, gap: -0.5, invTTC: 0)
        XCTAssertEqual(run(ThreatEngine(), t, frames: 10)?.level, 0)
    }

    func testSlowVehicleHasNoCaution() {
        // bikeSpeed 1 + z*invTTC 0.5 = 1.5 m/s < 2.8: caution band suppressed, threat kept.
        let t = TrackState(id: 1, cls: .car, z: 5, gap: -1.2, invTTC: 0.1)
        XCTAssertEqual(run(ThreatEngine(), t, frames: 10, speed: 1)?.level, 0)
        let close = TrackState(id: 1, cls: .car, z: 5, gap: -0.8, invTTC: 0.1)
        XCTAssertEqual(run(ThreatEngine(), close, frames: 10, speed: 1)?.level, 2)
    }

    // The level holds for as long as the threat lasts (the front stays red); buzzing once
    // per escalation is RearWorker.driveHaptics' job, not the engine's.
    func testLevelPersistsThenEscalates() {
        let e = ThreatEngine()
        XCTAssertEqual(run(e, car(gap: -0.8), frames: 4)?.level, 2)
        let after = run(e, car(gap: -0.8), frames: 1, from: 1)
        XCTAssertEqual(after?.level, 2)
        XCTAssertEqual(after?.grip, "L")
        let imminent = TrackState(id: 1, cls: .car, z: 10, gap: -0.5, invTTC: 1)
        XCTAssertEqual(run(e, imminent, frames: 1, from: 2)?.level, 3)
        XCTAssertEqual(run(e, imminent, frames: 1, from: 3)?.level, 3)
    }

    func testRightHookHoldPersistsAfterTrackDisappears() {
        let e = ThreatEngine()
        let t = car(gap: -2.5, turnR: true)
        let d = run(e, t, frames: 4)
        XCTAssertEqual(d?.level, 2)
        XCTAssertEqual(d?.grip, "R")
        let held = e.update(tracks: [], bikeSpeed: 5, demoMode: false, now: 1.0)
        XCTAssertEqual(held, [Decision(id: 1, level: 2, grip: "R")])
        XCTAssertFalse(e.update(tracks: [], bikeSpeed: 5, demoMode: false, now: 2.9).isEmpty)
        XCTAssertTrue(e.update(tracks: [], bikeSpeed: 5, demoMode: false, now: 3.3).isEmpty)
    }

    func testBicycleOnlyInDemoMode() {
        let t = car(gap: -0.5, cls: .bicycle)
        XCTAssertNil(run(ThreatEngine(), t, frames: 4))
        XCTAssertEqual(run(ThreatEngine(), t, frames: 4, demo: true)?.level, 2)
    }

    func testForgetsAfterSixtySeconds() {
        let e = ThreatEngine()
        _ = run(e, car(gap: -0.8), frames: 4)
        _ = e.update(tracks: [], bikeSpeed: 5, demoMode: false, now: 70)
        // memory gone: alert-once no longer applies, so the full debounce+alert runs again
        XCTAssertEqual(run(e, car(gap: -0.8), frames: 4, from: 71)?.level, 2)
    }
}
