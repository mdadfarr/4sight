// DangerEngineTests.swift
//
// XCTest port of ml/test_danger.py (25 cases). XCTest is absent from the Command
// Line Tools, so the same scenarios also run as asserts in `swift run Checks`.

import XCTest
@testable import ThreatEngine

final class DangerEngineTests: XCTestCase {
    let dt = 0.1  // 10 frames per second

    /// Box widths of a vehicle closing at `speed` m/s, one per frame.
    /// The last frame is exactly `ttcEnd` seconds before it reaches the bike.
    func closingWidths(ttcEnd: Double, n: Int = 6, speed: Double = 8.0, k: Double = 2000.0) -> [Double] {
        let endDistance = ttcEnd * speed
        return (0..<n).map { i in k / (endDistance + speed * Double(n - 1 - i) * dt) }
    }

    func fresh(mirror: Bool = true, frameWidth: Double = 640,
               jumpRatio: Double = 1.6, zones: [ExclusionZone] = []) -> DangerEngine {
        var c = DangerConfig()
        c.frameWidth = frameWidth
        c.frameHeight = 360
        c.mirror = mirror
        c.jumpRatio = jumpRatio
        c.exclusionZones = zones
        return DangerEngine(config: c)
    }

    /// Feed one vehicle's box widths, one per frame. `lateral` places the vehicle
    /// off the camera's centre line in units of its own width (negative = left of
    /// the picture), so the box centre moves outward as it grows, as for a real
    /// vehicle in a fixed lane.
    func feed(_ engine: DangerEngine, _ widths: [Double], cx: Double = 320,
              trackID: Int = 1, start: Double = 0, lateral: Double? = nil,
              centerY: Double? = nil, confidence: Double = 1.0) -> DangerOutput {
        var out = DangerOutput()
        for (i, w) in widths.enumerated() {
            let x = lateral.map { 320 + $0 * w } ?? cx
            out = engine.update(time: start + Double(i) * dt, detections: [
                DangerDetection(trackID: trackID, centerX: x, width: w, centerY: centerY, confidence: confidence)
            ])
        }
        return out
    }

    /// Same, with a different lateral offset for every frame.
    func feedSliding(_ engine: DangerEngine, _ widths: [Double], laterals: [Double]) -> DangerOutput {
        var out = DangerOutput()
        for (i, w) in widths.enumerated() {
            out = engine.update(time: Double(i) * dt, detections: [
                DangerDetection(trackID: 1, centerX: 320 + laterals[i] * w, width: w)
            ])
        }
        return out
    }

    // ---- approaching vehicles ----

    func testTimeToCollisionMatchesTheTrueValue() {
        for trueTTC in [1.2, 2.0, 2.5] {
            let out = feed(fresh(), closingWidths(ttcEnd: trueTTC))
            XCTAssertEqual(out.vehicles.first?.ttcSeconds ?? -1, trueTTC, accuracy: 0.1)
        }
    }

    func testWarningBetweenTwoAndThreeSeconds() {
        let out = feed(fresh(), closingWidths(ttcEnd: 2.5))
        XCTAssertEqual(out.left, .warning)
        XCTAssertEqual(out.right, .warning)   // centre = both handles
    }

    func testUrgentUnderTwoSeconds() {
        XCTAssertEqual(feed(fresh(), closingWidths(ttcEnd: 1.5)).left, .urgent)
    }

    func testNoAlertWhileStillFar() {
        let out = feed(fresh(), closingWidths(ttcEnd: 4.0))
        XCTAssertEqual(out.left, .off)
        XCTAssertEqual(out.right, .off)
    }

    func testAlertStartsNearThreeSecondsAndGetsStronger() {
        let eng = fresh()
        var firstWarn: Double?
        var firstUrgent: Double?
        for i in 0..<50 {
            let t = Double(i) * dt
            let trueTTC = (40 - 8 * t) / 8
            let out = eng.update(time: t, detections: [
                DangerDetection(trackID: 1, centerX: 320, width: 2000 / (40 - 8 * t))
            ])
            if out.left >= .warning && firstWarn == nil { firstWarn = trueTTC }
            if out.left >= .urgent && firstUrgent == nil { firstUrgent = trueTTC }
        }
        XCTAssertGreaterThan(firstWarn ?? 0, 2.6)
        XCTAssertLessThanOrEqual(firstWarn ?? 99, 3.0)
        XCTAssertGreaterThan(firstUrgent ?? 0, 1.6)
        XCTAssertLessThanOrEqual(firstUrgent ?? 99, 2.0)
    }

    func testJitteryWidthsUseTheTrendNotTheLastTwoFrames() {
        let out = feed(fresh(), [60, 63, 59, 66, 70, 76])
        let ttc = out.vehicles.first?.ttcSeconds ?? 0
        XCTAssertGreaterThan(ttc, 1.8)
        XCTAssertLessThan(ttc, 2.3)
        XCTAssertGreaterThanOrEqual(out.left, .warning)
    }

    // ---- slow and still vehicles ----

    func testCarCreepingCloseGetsTheGentleLevel() {
        let out = feed(fresh(), [390, 392, 394, 396, 398, 400])
        XCTAssertGreaterThan(out.vehicles.first?.ttcSeconds ?? 0, 15)
        XCTAssertEqual(out.left, .gentle)
        XCTAssertEqual(out.right, .gentle)
    }

    func testFarCreepingCarGetsNothing() {
        let out = feed(fresh(), [90, 92, 94, 96, 98, 100])
        XCTAssertEqual(out.left, .off)
        XCTAssertEqual(out.right, .off)
    }

    func testStoppedCloseCarGetsNothing() {
        let out = feed(fresh(), [Double](repeating: 400, count: 8))
        XCTAssertEqual(out.left, .off)
        XCTAssertEqual(out.right, .off)
    }

    func testRecedingCarGetsNothing() {
        let out = feed(fresh(), [400, 390, 380, 370, 360, 350])
        XCTAssertEqual(out.left, .off)
        XCTAssertEqual(out.right, .off)
    }

    // ---- robustness ----

    func testNeedsEnoughFramesBeforeAlerting() {
        let out = feed(fresh(), Array(closingWidths(ttcEnd: 1.5).prefix(3)))
        XCTAssertEqual(out.left, .off)
    }

    func testUntrackedDetectionsAreIgnored() {
        let eng = fresh()
        var out = DangerOutput()
        for (i, w) in closingWidths(ttcEnd: 1.5).enumerated() {
            out = eng.update(time: Double(i) * dt,
                             detections: [DangerDetection(trackID: -1, centerX: 320, width: w)])
        }
        XCTAssertEqual(out.left, .off)
    }

    func testResolutionDoesNotMatter() {
        let out = feed(fresh(frameWidth: 1280), closingWidths(ttcEnd: 1.5).map { $0 * 2 }, cx: 640)
        XCTAssertEqual(out.left, .urgent)
    }

    // ---- sides ----

    func testSidesAreFlippedForARearCamera() {
        let fast = closingWidths(ttcEnd: 1.5)
        var out = feed(fresh(), fast, lateral: -0.8)   // left of the picture = rider's right
        XCTAssertEqual(out.right, .urgent)
        XCTAssertEqual(out.left, .off)
        out = feed(fresh(), fast, lateral: 0.8)        // right of the picture = rider's left
        XCTAssertEqual(out.left, .urgent)
        XCTAssertEqual(out.right, .off)
        out = feed(fresh(), fast, lateral: 0)          // middle = directly behind
        XCTAssertEqual(out.left, .urgent)
        XCTAssertEqual(out.right, .urgent)
    }

    func testMirrorCanBeTurnedOff() {
        let out = feed(fresh(mirror: false), closingWidths(ttcEnd: 1.5), lateral: -0.8)
        XCTAssertEqual(out.left, .urgent)
        XCTAssertEqual(out.right, .off)
    }

    func testTwoVehiclesOnOppositeSidesUseBothHandles() {
        let eng = fresh()
        var out = DangerOutput()
        for (i, w) in closingWidths(ttcEnd: 1.5).enumerated() {
            out = eng.update(time: Double(i) * dt, detections: [
                DangerDetection(trackID: 1, centerX: 320 - 0.8 * w, width: w),
                DangerDetection(trackID: 2, centerX: 320 + 0.8 * w, width: w),
            ])
        }
        XCTAssertEqual(out.left, .urgent)
        XCTAssertEqual(out.right, .urgent)
    }

    // ---- the four filters ----

    func testCarInTheNextLaneIsAPassNotACollision() {
        let out = feed(fresh(), closingWidths(ttcEnd: 1.5), lateral: 1.5)
        XCTAssertEqual(out.left, .off)
        XCTAssertEqual(out.right, .off)
    }

    func testCarSlidingSidewaysAcrossThePictureIsIgnored() {
        let slide: [Double] = [0.3, 0.5, 0.7, 0.9, 1.2, 1.5]
        let out = feedSliding(fresh(), closingWidths(ttcEnd: 1.5), laterals: slide)
        XCTAssertEqual(out.left, .off)
        XCTAssertEqual(out.right, .off)
    }

    func testCarCloseToTheCentreLineStillAlerts() {
        let out = feed(fresh(), closingWidths(ttcEnd: 1.5), lateral: 0.5)
        XCTAssertTrue(out.left == .urgent || out.right == .urgent)
    }

    func testTinyFarBoxesAreIgnored() {
        let tiny = closingWidths(ttcEnd: 1.5).map { $0 * 0.1 }
        let out = feed(fresh(), tiny)
        XCTAssertEqual(out.left, .off)
        XCTAssertEqual(out.right, .off)
    }

    func testAVideoCutDoesNotCauseAnAlert() {
        let eng = fresh()
        _ = feed(eng, [Double](repeating: 60, count: 8))
        let out = feed(eng, [Double](repeating: 300, count: 3), start: 8 * dt)
        XCTAssertEqual(out.left, .off)
        XCTAssertEqual(out.right, .off)
    }

    func testTheCutRuleIsWhatPreventsThatAlert() {
        // With the reset rule switched off, the same cut does produce an alert.
        let eng = fresh(jumpRatio: 1e9)
        _ = feed(eng, [Double](repeating: 60, count: 8))
        let out = feed(eng, [Double](repeating: 300, count: 3), start: 8 * dt)
        XCTAssertTrue(out.left >= .warning || out.right >= .warning)
    }

    func testDetectionsInAnExclusionZoneAreIgnored() {
        let big = closingWidths(ttcEnd: 1.5, k: 4000)   // 250 to 333 px
        let zone = [ExclusionZone(x1: 0, y1: 0.5, x2: 1, y2: 1)]
        var out = feed(fresh(zones: zone), big, cx: 320, centerY: 300)   // inside the zone
        XCTAssertEqual(out.left, .off)
        XCTAssertEqual(out.right, .off)
        out = feed(fresh(zones: zone), big, cx: 320, centerY: 100)       // outside the zone
        XCTAssertEqual(out.left, .urgent)
    }

    func testHugeUnsureBoxesAreIgnoredButHugeSureOnesAreNot() {
        let big = closingWidths(ttcEnd: 1.5, k: 6000)   // 375 to 500 px in every frame
        var out = feed(fresh(), big, confidence: 0.35)
        XCTAssertEqual(out.left, .off)
        XCTAssertEqual(out.right, .off)
        out = feed(fresh(), big, confidence: 0.9)
        XCTAssertEqual(out.left, .urgent)
    }

    // ---- timing ----

    func testAlertIsHeldForASecondThenReleased() {
        let eng = fresh()
        _ = feed(eng, closingWidths(ttcEnd: 1.5), lateral: -0.8)   // alert on the right at t = 0.5
        XCTAssertEqual(eng.update(time: 1.0, detections: []).right, .urgent)
        XCTAssertEqual(eng.update(time: 1.4, detections: []).right, .urgent)
        XCTAssertEqual(eng.update(time: 1.6, detections: []).right, .off)
    }
}
