import Foundation
import ThreatEngine

// Port of ml/test_danger.py (25) + ml/test_tracker.py (6) as asserts; see DangerEngineTests.swift.
private let dt = 0.1

private func closingWidths(ttcEnd: Double, n: Int = 6, speed: Double = 8.0, k: Double = 2000.0) -> [Double] {
    let endDistance = ttcEnd * speed
    return (0..<n).map { i in k / (endDistance + speed * Double(n - 1 - i) * dt) }
}

private func fresh(mirror: Bool = true, frameWidth: Double = 640, jumpRatio: Double = 1.6,
                   zones: [ExclusionZone] = []) -> DangerEngine {
    var c = DangerConfig()
    c.frameWidth = frameWidth; c.frameHeight = 360; c.mirror = mirror
    c.jumpRatio = jumpRatio; c.exclusionZones = zones
    return DangerEngine(config: c)
}

@discardableResult
private func feed(_ engine: DangerEngine, _ widths: [Double], cx: Double = 320, trackID: Int = 1,
                  start: Double = 0, lateral: Double? = nil, centerY: Double? = nil,
                  confidence: Double = 1.0) -> DangerOutput {
    var out = DangerOutput()
    for (i, w) in widths.enumerated() {
        let x = lateral.map { 320 + $0 * w } ?? cx
        out = engine.update(time: start + Double(i) * dt, detections: [
            DangerDetection(trackID: trackID, centerX: x, width: w, centerY: centerY, confidence: confidence)])
    }
    return out
}

private func car(_ cx: Double, _ half: Double) -> SimpleBox {
    SimpleBox(x1: cx - half, y1: 100, x2: cx + half, y2: 100 + half)
}

func runDangerChecks() {
    // approaching vehicles
    for trueTTC in [1.2, 2.0, 2.5] {
        let ttc = feed(fresh(), closingWidths(ttcEnd: trueTTC)).vehicles.first?.ttcSeconds ?? -1
        check(near(ttc, trueTTC, 0.1), "danger: ttc \(ttc) ≈ \(trueTTC)")
    }
    var out = feed(fresh(), closingWidths(ttcEnd: 2.5))
    check(out.left == .warning && out.right == .warning, "danger: warning between 2 and 3 s, both handles")
    check(feed(fresh(), closingWidths(ttcEnd: 1.5)).left == .urgent, "danger: urgent under 2 s")
    out = feed(fresh(), closingWidths(ttcEnd: 4.0))
    check(out.left == .off && out.right == .off, "danger: no alert while still far")
    do {
        let eng = fresh(); var firstWarn: Double?; var firstUrgent: Double?
        for i in 0..<50 {
            let t = Double(i) * dt, trueTTC = (40 - 8 * t) / 8
            let o = eng.update(time: t, detections: [DangerDetection(trackID: 1, centerX: 320, width: 2000 / (40 - 8 * t))])
            if o.left >= .warning && firstWarn == nil { firstWarn = trueTTC }
            if o.left >= .urgent && firstUrgent == nil { firstUrgent = trueTTC }
        }
        check((firstWarn ?? 0) > 2.6 && (firstWarn ?? 99) <= 3.0 && (firstUrgent ?? 0) > 1.6 && (firstUrgent ?? 99) <= 2.0,
              "danger: alert starts near 3 s (\(firstWarn ?? -1)) and strengthens near 2 s (\(firstUrgent ?? -1))")
    }
    out = feed(fresh(), [60, 63, 59, 66, 70, 76])
    let jit = out.vehicles.first?.ttcSeconds ?? 0
    check(jit > 1.8 && jit < 2.3 && out.left >= .warning, "danger: jittery widths use the trend")
    // slow and still
    out = feed(fresh(), [390, 392, 394, 396, 398, 400])
    check((out.vehicles.first?.ttcSeconds ?? 0) > 15 && out.left == .gentle && out.right == .gentle, "danger: creeping close car -> gentle")
    out = feed(fresh(), [90, 92, 94, 96, 98, 100])
    check(out.left == .off && out.right == .off, "danger: far creeping car -> nothing")
    out = feed(fresh(), [Double](repeating: 400, count: 8))
    check(out.left == .off && out.right == .off, "danger: stopped close car -> nothing")
    out = feed(fresh(), [400, 390, 380, 370, 360, 350])
    check(out.left == .off && out.right == .off, "danger: receding car -> nothing")
    // robustness
    check(feed(fresh(), Array(closingWidths(ttcEnd: 1.5).prefix(3))).left == .off, "danger: needs enough frames")
    check(feed(fresh(), closingWidths(ttcEnd: 1.5), trackID: -1).left == .off, "danger: untracked ignored")
    check(feed(fresh(frameWidth: 1280), closingWidths(ttcEnd: 1.5).map { $0 * 2 }, cx: 640).left == .urgent, "danger: resolution independent")
    // sides
    let fast = closingWidths(ttcEnd: 1.5)
    out = feed(fresh(), fast, lateral: -0.8)
    check(out.right == .urgent && out.left == .off, "danger: image left -> rider's right (mirror)")
    out = feed(fresh(), fast, lateral: 0.8)
    check(out.left == .urgent && out.right == .off, "danger: image right -> rider's left (mirror)")
    out = feed(fresh(), fast, lateral: 0)
    check(out.left == .urgent && out.right == .urgent, "danger: middle -> both")
    out = feed(fresh(mirror: false), fast, lateral: -0.8)
    check(out.left == .urgent && out.right == .off, "danger: mirror off")
    do {
        let eng = fresh(); var o = DangerOutput()
        for (i, w) in fast.enumerated() {
            o = eng.update(time: Double(i) * dt, detections: [
                DangerDetection(trackID: 1, centerX: 320 - 0.8 * w, width: w),
                DangerDetection(trackID: 2, centerX: 320 + 0.8 * w, width: w)])
        }
        check(o.left == .urgent && o.right == .urgent, "danger: two vehicles, both handles")
    }
    // passing check + four filters
    out = feed(fresh(), fast, lateral: 1.5)
    check(out.left == .off && out.right == .off, "danger: next lane is a pass")
    do {
        let eng = fresh(); var o = DangerOutput()
        for (i, (w, l)) in zip(fast, [0.3, 0.5, 0.7, 0.9, 1.2, 1.5]).enumerated() {
            o = eng.update(time: Double(i) * dt, detections: [DangerDetection(trackID: 1, centerX: 320 + l * w, width: w)])
        }
        check(o.left == .off && o.right == .off, "danger: sliding sideways ignored")
    }
    out = feed(fresh(), fast, lateral: 0.5)
    check(out.left == .urgent || out.right == .urgent, "danger: near centre line still alerts")
    out = feed(fresh(), fast.map { $0 * 0.1 })
    check(out.left == .off && out.right == .off, "danger: filter 1 tiny boxes ignored")
    do {
        let eng = fresh(); feed(eng, [Double](repeating: 60, count: 8))
        let o = feed(eng, [Double](repeating: 300, count: 3), start: 8 * dt)
        check(o.left == .off && o.right == .off, "danger: filter 4 video cut -> no alert")
        let eng2 = fresh(jumpRatio: 1e9); feed(eng2, [Double](repeating: 60, count: 8))
        let o2 = feed(eng2, [Double](repeating: 300, count: 3), start: 8 * dt)
        check(o2.left >= .warning || o2.right >= .warning, "danger: without the jump rule the cut alerts")
    }
    do {
        let big = closingWidths(ttcEnd: 1.5, k: 4000)
        let zone = [ExclusionZone(x1: 0, y1: 0.5, x2: 1, y2: 1)]
        let o = feed(fresh(zones: zone), big, cx: 320, centerY: 300)
        check(o.left == .off && o.right == .off, "danger: filter 2 exclusion zone ignored")
        check(feed(fresh(zones: zone), big, cx: 320, centerY: 100).left == .urgent, "danger: outside zone alerts")
    }
    do {
        let big = closingWidths(ttcEnd: 1.5, k: 6000)
        let o = feed(fresh(), big, confidence: 0.35)
        check(o.left == .off && o.right == .off, "danger: filter 3 huge unsure ignored")
        check(feed(fresh(), big, confidence: 0.9).left == .urgent, "danger: huge sure alerts")
    }
    // hold
    do {
        let eng = fresh(); feed(eng, fast, lateral: -0.8)
        check(eng.update(time: 1.0, detections: []).right == .urgent
              && eng.update(time: 1.4, detections: []).right == .urgent
              && eng.update(time: 1.6, detections: []).right == .off, "danger: 1 s hold then release")
    }

    // SimpleTracker
    let sq = SimpleBox(x1: 0, y1: 0, x2: 10, y2: 10)
    check(near(iou(sq, sq), 1, 1e-9) && near(iou(sq, SimpleBox(x1: 20, y1: 20, x2: 30, y2: 30)), 0, 1e-9)
          && near(iou(sq, SimpleBox(x1: 5, y1: 0, x2: 15, y2: 10)), 1.0 / 3, 1e-9), "tracker: iou basics")
    do {
        let tr = SimpleTracker(); var ids = Set<Int>()
        for i in 0..<10 { ids.insert(tr.update([car(300, 30 + 4 * Double(i))])[0]) }
        check(ids.count == 1, "tracker: growing car keeps id")
    }
    do {
        let tr = SimpleTracker(); let first = tr.update([car(100, 30), car(500, 30)]); var ids = first
        for i in 1..<6 { let d = Double(i); ids = tr.update([car(100 + 2 * d, 30 + d), car(500 - 2 * d, 30 + d)]) }
        check(ids == first && first[0] != first[1], "tracker: two cars keep separate ids")
    }
    do {
        let tr = SimpleTracker(); let a = tr.update([car(100, 30)])[0]
        let ids = tr.update([car(102, 31), car(500, 30)])
        check(ids[0] == a && ids[1] != a, "tracker: new car gets new id")
    }
    do {
        let tr = SimpleTracker(maxMissed: 5); let a = tr.update([car(300, 40)])[0]
        for _ in 0..<3 { _ = tr.update([]) }
        check(tr.update([car(302, 41)])[0] == a, "tracker: brief vanish keeps id")
    }
    do {
        let tr = SimpleTracker(maxMissed: 5); let a = tr.update([car(300, 40)])[0]
        for _ in 0..<7 { _ = tr.update([]) }
        check(tr.update([car(302, 41)])[0] != a, "tracker: long vanish -> new id")
    }
}
