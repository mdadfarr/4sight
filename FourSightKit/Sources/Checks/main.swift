import Foundation
import Protocol
import ThreatEngine
import Perception

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print((ok ? "  ok  " : " FAIL ") + what)
    if !ok { failures += 1 }
}
func near(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }

// Protocol
let example = """
{"t":1712.43,"fps":24,"temp":"nominal","speed":5.3,"heading":182.0,"demo":false,
 "tracks":[{"id":7,"cls":"car","x":-1.4,"z":18.2,"inv_ttc":0.21,
            "gap_pred":0.8,"level":2,"grip":"L","turn_r":false}]}
"""
do {
    let msg = try FrameMessage.decode(line: example)
    let line = try msg.encodeLine()
    let text = String(decoding: line, as: UTF8.self)
    check(msg.tracks[0].invTTC == 0.21 && msg.tracks[0].grip == "L", "decode example")
    check(line.last == 0x0A && ["inv_ttc", "gap_pred", "turn_r"].allSatisfy { text.contains("\"\($0)\"") }, "encode keys + newline")
    check(try FrameMessage.decode(line: line) == msg, "round trip")
} catch { check(false, "protocol threw \(error)") }
check(BLECommand.left(level: 1).ascii == "L1" && BLECommand.right(level: 3).ascii == "R3"
      && BLECommand.clear.ascii == "X" && BLECommand.heartbeat.ascii == "H", "BLE strings")

// ThreatEngine
func run(_ e: ThreatEngine, _ t: TrackState, frames: Int, speed: Double = 5, demo: Bool = false, from: Double = 0) -> Decision? {
    var last: Decision?
    for i in 0..<frames { last = e.update(tracks: [t], bikeSpeed: speed, demoMode: demo, now: from + Double(i) * 0.05).first }
    return last
}
func car(_ gap: Double, cls: VehicleClass = .car, turnR: Bool = false) -> TrackState {
    TrackState(id: 1, cls: cls, z: 20, gap: gap, invTTC: 0.2, turnR: turnR)
}
do {
    let e = ThreatEngine()
    check(run(e, car(-0.8), frames: 3)?.level == 1, "debounce holds level <2 for 3 frames")
    let d = run(e, car(-0.8), frames: 1, from: 1)
    check(d?.level == 2 && d?.grip == "L", "closing car 0.8 m -> level 2 grip L")
    check(run(e, car(-0.8), frames: 1, from: 2)?.level == 2, "threat stays red while it lasts")
    let imm = TrackState(id: 1, cls: .car, z: 10, gap: -0.5, invTTC: 1)
    check(run(e, imm, frames: 1, from: 3)?.level == 3, "escalates to imminent")
    check(run(e, imm, frames: 1, from: 4)?.level == 3, "imminent stays imminent while it lasts")
}
check(run(ThreatEngine(), car(-1.2), frames: 10)?.level == 1, "1.2 m -> caution only")
check(run(ThreatEngine(), car(-2.0), frames: 10)?.level == 0, "2.0 m -> level 0")
check(run(ThreatEngine(), car(-1.3, cls: .bus), frames: 4)?.level == 2, "bus 1.3 m -> threat")
check(run(ThreatEngine(), TrackState(id: 1, cls: .car, z: 10, gap: -0.5, invTTC: 1), frames: 4)?.level == 3, "aReq 5 -> imminent")
check(run(ThreatEngine(), TrackState(id: 1, cls: .car, z: 10, gap: -0.5, invTTC: 0), frames: 10)?.level == 0, "parked car silent")
check(run(ThreatEngine(), TrackState(id: 1, cls: .car, z: 5, gap: -1.2, invTTC: 0.1), frames: 10, speed: 1)?.level == 0, "slow vehicle: no caution")
check(run(ThreatEngine(), TrackState(id: 1, cls: .car, z: 5, gap: -1.2, invTTC: 0.1), frames: 10, speed: 0)?.level == 1, "bike speed unknown (0): slow rule off, caution kept")
do {
    let wide = run(ThreatEngine(), TrackState(id: 1, cls: .car, z: 20, gap: -2.0, gapVelocity: -5, invTTC: 0.05), frames: 10)
    check(wide?.level == 0 && near(wide?.gapPred ?? 0, 6.5, 1e-9), "fast lateral pass: gap velocity clamped to 1.5 m/s x 3 s -> 6.5 m, level 0")
    let drift = run(ThreatEngine(), TrackState(id: 1, cls: .car, z: 20, gap: -1.4, gapVelocity: 0.3, invTTC: 0.3), frames: 4)
    check(drift?.level == 2 && near(drift?.gapPred ?? 0, 0.5, 1e-9), "drifting toward bike: 1.4 - 0.3 x 3 s -> 0.5 m, level 2")
}
check(run(ThreatEngine(), car(-0.5, cls: .bicycle), frames: 4) == nil, "bicycle ignored outside demo")
check(run(ThreatEngine(), car(-0.5, cls: .bicycle), frames: 4, demo: true)?.level == 2, "bicycle threat in demo")
do {
    let e = ThreatEngine()
    let d = run(e, car(-2.5, turnR: true), frames: 4)
    check(d?.level == 2 && d?.grip == "R", "right hook -> level 2 grip R")
    check(e.update(tracks: [], bikeSpeed: 5, demoMode: false, now: 1.0) == [Decision(id: 1, level: 2, grip: "R")], "hold while absent")
    check(e.update(tracks: [], bikeSpeed: 5, demoMode: false, now: 3.3).isEmpty, "hold expires after 3 s")
}

// Tracker
do {
    let tr = Tracker()
    var ids = Set<Int>(), counts = Set<Int>()
    for i in 0..<20 {
        let out = tr.update(detections: [Detection(box: Box(x: 100 + Double(i) * 8, y: 200, w: 120, h: 90), cls: .car, confidence: 0.8)], dt: 1 / 30)
        if i >= 1 { ids.formUnion(out.map(\.id)); counts.insert(out.count) }
    }
    check(ids.count == 1 && counts == [1], "moving box keeps one id")
    let tr2 = Tracker()
    var pairs = Set<[Int]>()
    for i in 0..<20 {
        let a = Detection(box: Box(x: 100 + Double(i) * 5, y: 200, w: 100, h: 80), cls: .car, confidence: 0.9)
        let b = Detection(box: Box(x: 700 - Double(i) * 5, y: 300, w: 140, h: 100), cls: .truck, confidence: 0.6)
        let out = tr2.update(detections: [a, b], dt: 1 / 30)
        if i >= 1 { pairs.insert(out.sorted { $0.box.x < $1.box.x }.map(\.id)) }
    }
    check(pairs.count == 1 && Set(pairs.first ?? []).count == 2, "two boxes keep distinct ids")
    // Night drive: a fast passing car with glare-jittered size and a 1 s detector dropout (10 fps).
    let tr3 = Tracker(); var ids3 = Set<Int>()
    for i in 0..<40 {
        let j = i % 2 == 0 ? 1.15 : 0.87, cx = 1000 - Double(i) * 30
        let dets = (12...21).contains(i) ? [] : [Detection(box: Box(x: cx - 75 * j, y: 570 - 40 * j, w: 150 * j, h: 80 * j), cls: .car, confidence: i % 3 == 0 ? 0.3 : 0.7)]
        ids3.formUnion(tr3.update(detections: dets, dt: 0.1).map(\.id))
    }
    check(ids3.count == 1, "jittered fast car with 1 s dropout keeps one id (\(ids3.count))")
    // Ride footage: a person close behind walks across the frame faster than their own
    // width per frame at 10 fps, so IoU with the last box is zero.
    let tr4 = Tracker(); var ids4 = Set<Int>(), most4 = 0
    for i in 0..<20 {
        let out = tr4.update(detections: [Detection(box: Box(x: 100 + Double(i) * 70, y: 100, w: 90, h: 400), cls: .person, confidence: 0.8)], dt: 0.1)
        ids4.formUnion(out.map(\.id)); most4 = max(most4, out.filter { $0.misses == 0 }.count)
    }
    check(ids4.count == 1 && most4 == 1, "fast close person keeps one id (\(ids4.count) ids)")
    // The detector double-fires on one person (whole body and upper body).
    let tr5 = Tracker(); var ids5 = Set<Int>()
    for _ in 0..<10 {
        let whole = Detection(box: Box(x: 300, y: 100, w: 120, h: 400), cls: .person, confidence: 0.9)
        let upper = Detection(box: Box(x: 305, y: 100, w: 110, h: 200), cls: .person, confidence: 0.6)
        ids5.formUnion(tr5.update(detections: [whole, upper], dt: 0.1).map(\.id))
    }
    check(ids5.count == 1, "double detection on one person -> one id (\(ids5.count))")
    // Two people walking side by side must stay two.
    let tr6 = Tracker(); var n6 = Set<Int>()
    for i in 0..<10 {
        let a = Detection(box: Box(x: 300 + Double(i) * 5, y: 100, w: 100, h: 380), cls: .person, confidence: 0.8)
        let b = Detection(box: Box(x: 420 + Double(i) * 5, y: 110, w: 100, h: 370), cls: .person, confidence: 0.8)
        n6.insert(tr6.update(detections: [a, b], dt: 0.1).count)
    }
    check(n6.subtracting([0]) == [2], "two people side by side stay two tracks")
}

// Camera mounted off the centreline
do {
    var g = GapEstimator(f: 750, u0: 533, v0: 300, imageW: 1066, imageH: 600)
    g.cameraOffset = 0.10
    // A car whose near edge sits exactly on the optical axis is straight behind the lens,
    // so 0.10 m to the rider's right of the bike, not on its centreline.
    let b = Box(x: 533, y: 250, w: 100, h: 60)
    check(near(g.gap(box: b, cls: .car, z: 10), 0.10, 1e-9), "camera offset: on-axis car sits at the lens offset")
}

// Ego mask: the rear wheel under the camera
do {
    let W = 1066.0, H = 600.0
    func det(_ cx: Double, _ cy: Double, _ w: Double, _ h: Double, _ cls: VehicleClass = .person) -> Detection {
        Detection(box: Box(x: (cx - w / 2) * W, y: (cy - h / 2) * H, w: w * W, h: h * H), cls: cls, confidence: 0.3)
    }
    var m = EgoMask()
    var t = 0.0, kept: [Detection] = []
    // The wheel as the footage showed it: bottom right, 0.22 x 0.2 of the frame, jittering.
    for i in 0..<30 {
        let j = Double(i % 3) * 0.005
        kept = m.apply([det(0.70 + j, 0.89 - j, 0.23, 0.20)], imageW: W, imageH: H, t: t); t += 0.1
    }
    check(kept.isEmpty && m.zones.count == 1, "ego mask: still bottom-anchored wheel learned and dropped")
    // A real person walking up the middle of the frame is untouched.
    check(m.apply([det(0.45, 0.5, 0.15, 0.6)], imageW: W, imageH: H, t: t).count == 1,
          "ego mask: person elsewhere still detected")
    // A car right behind, filling the frame bottom, is never masked even over the wheel.
    check(m.apply([det(0.65, 0.7, 0.6, 0.6, .car)], imageW: W, imageH: H, t: t).count == 1,
          "ego mask: large close vehicle over the wheel zone is kept")
    // Something bottom-anchored but moving across never becomes a zone.
    var m2 = EgoMask(); var t2 = 0.0
    for i in 0..<30 { _ = m2.apply([det(0.2 + Double(i) * 0.02, 0.9, 0.15, 0.18)], imageW: W, imageH: H, t: t2); t2 += 0.1 }
    check(m2.zones.isEmpty, "ego mask: moving bottom object is not learned")
}

// TTC
do {
    let est = TTCEstimator(); let T = 10.0; var t = 0.0; var r: Double?
    while t < 4 { let s = 100 / (T - t); r = est.update(id: 1, box: Box(x: 0, y: 0, w: s, h: s), t: t, touchesEdge: false); t += 1 / 30 }
    let truth = 1 / (T - (t - 1 / 30))
    check(r != nil && near(r!, truth, truth * 0.15), "invTTC \(r ?? -1) vs \(truth) within 15%")
}

// DetectionFilter
do {
    var f = DetectionFilter()
    f.exclusionZones = [DetectionFilter.Zone("0,0.5,1,1")!]
    let W = 640.0, H = 360.0
    func det(w: Double, cy: Double = 100, conf: Double = 0.9) -> Detection {
        Detection(box: Box(x: 320 - w / 2, y: cy - 20, w: w, h: 40), cls: .car, confidence: conf)
    }
    check(!f.keep(det(w: 20), imageW: W, imageH: H), "filter: < 4% width dropped")
    check(f.keep(det(w: 40), imageW: W, imageH: H), "filter: 6% width kept")
    check(!f.keep(det(w: 400, conf: 0.35), imageW: W, imageH: H) && f.keep(det(w: 400, conf: 0.9), imageW: W, imageH: H), "filter: large+unsure dropped, large+sure kept")
    check(!f.keep(det(w: 100, cy: 300), imageW: W, imageH: H), "filter: exclusion zone dropped")
    check(DetectionFilter.Zone("0.4,0,1") == nil, "filter: bad zone text -> nil")
    check(!f.jumped(id: 1, box: Box(x: 0, y: 0, w: 60, h: 40), imageW: W), "filter: first frame no jump")
    check(!f.jumped(id: 1, box: Box(x: 0, y: 0, w: 70, h: 40), imageW: W), "filter: 60->70 no jump")
    check(f.jumped(id: 1, box: Box(x: 0, y: 0, w: 300, h: 40), imageW: W), "filter: 70->300 jump")
}

// Gap
do {
    let est = GapEstimator(f: 1000, u0: 640, v0: 360, imageW: 1280, imageH: 720)
    check(near(est.gap(box: Box(x: 700, y: 300, w: 200, h: 100), cls: .car, z: 20), -1.47, 1e-9), "gap geometry un-mirrored -> -1.47")
    check(near(est.range(box: Box(x: 0, y: 310, w: 90, h: 100), cls: .car), 20, 1e-9), "ground-plane range 20 m")
    check(near(est.range(box: Box(x: 500, y: 620, w: 90, h: 100), cls: .car), 20, 1e-9), "width fallback 20 m")
    // People by apparent height: 1.7 m tall at 85 px with f=1000 is 20 m, wherever the feet are.
    check(near(est.range(box: Box(x: 0, y: 200, w: 30, h: 85), cls: .person), 20, 1e-9),
          "person range from height, 20 m")
    check(near(est.range(box: Box(x: 0, y: 450, w: 30, h: 85), cls: .person), 20, 1e-9),
          "person range ignores camera tilt (same height, lower in frame)")
    // Feet cut off by the bottom edge: the height is truncated, so it must not be used.
    check(est.range(box: Box(x: 600, y: 300, w: 30, h: 600), cls: .person) != 1000 * 1.7 / 600,
          "person cut off at the frame edge does not use truncated height")
    // A person 1 m away fills the frame top to bottom; 0.5 m wide at f=1000 is 500 px.
    // The old car-width fallback read 1000 * 1.8 / 500 = 3.6 m.
    let close = est.range(box: Box(x: 390, y: 0, w: 500, h: 720), cls: .person)
    check(near(close, 1, 0.05), "person 1 m away, cut off top and bottom -> \(String(format: "%.2f", close)) m, not 3.6")
    let portrait = GapEstimator(f: 1000, u0: 360, v0: 640, imageW: 720, imageH: 1280)
    check(near(portrait.range(box: Box(x: 110, y: 0, w: 500, h: 1280), cls: .person), 1, 0.05),
          "portrait frame: person 1 m away, cut off top and bottom -> 1 m")
    check(near(est.range(box: Box(x: 0, y: 0, w: 640, h: 720), cls: .person), 1000 * 0.5 / 640, 1e-9),
          "person cut off on all sides -> the smaller of height and width estimates")
    check(near(est.range(box: Box(x: 500, y: 400, w: 250, h: 320), cls: .bus), 10, 1e-9),
          "bus cut off at the bottom -> bus width 2.5 m, 10 m (car width read 7.2)")
}

// RangeFilter (10 Hz, the detector rate)
do {
    let rf = RangeFilter(); var dev = 0.0
    for i in 0..<20 { dev = max(dev, abs(rf.update(id: 1, z: i == 10 ? 1 : 4, t: Double(i) * 0.1) - 4)) }
    check(dev < 0.75, "range filter: one-frame 4 -> 1 m jump moves z by \(String(format: "%.2f", dev)) m (< 1/4 of the jump)")
    let rf2 = RangeFilter(); var z = 0.0
    for i in 0...20 { z = rf2.update(id: 1, z: i < 10 ? 4 : 1, t: Double(i) * 0.1) }
    check(near(z, 1, 0.1), "range filter: genuine 4 -> 1 m step within 1 s -> \(String(format: "%.2f", z)) m")
}

// Ride sidecars (replayed footage from tools/mcap_to_ride.py)
do {
    let json = #"{"f":1200.5,"u0":640.0,"v0":360.0,"width":1280,"height":720,"camera_height":1.4,"fps":20.0,"source":"bag.mcap"}"#
    if let cam = RideCamera(json: Data(json.utf8)) {
        check(near(cam.f, 1200.5, 1e-9) && cam.cameraHeight == 1.4, "camera.json parsed, extra keys ignored")
        let half = cam.scaled(toWidth: 640, height: 360)
        check(near(half.f, 600.25, 1e-9) && near(half.u0, 320, 1e-9) && half.cameraHeight == 1.4, "intrinsics scale, height does not")
    } else {
        check(false, "camera.json did not parse")
    }
    check(RideCamera(json: Data(#"{"frames":10}"#.utf8)) == nil, "camera.json without intrinsics -> nil")

    let jsonl = """
    {"t":104.0,"lat":43.77,"lon":-79.25,"speed":4.0,"heading":182.0}
    {"t":105.0,"lat":43.77,"lon":
    {"t":106.0,"lat":43.78,"lon":-79.26,"speed":6.0,"heading":184.0}
    {"t":108.0,"lat":43.79,"lon":-79.27,"speed":8.0,"heading":186.0}
    """
    if let track = RideTrack(jsonl: jsonl) {
        check(track.fixes.count == 3 && track.fixes.map(\.t) == [0, 2, 4], "jsonl: junk line skipped, t re-based")
        check(track.fix(at: -1)?.speed == 4 && track.fix(at: 1.9)?.speed == 4, "fix lookup holds before the next fix")
        check(track.fix(at: 2)?.speed == 6 && track.fix(at: 99)?.speed == 8, "fix lookup at and past the last fix")
    } else {
        check(false, "jsonl did not parse")
    }
    check(RideTrack(jsonl: "not json") == nil, "jsonl with no usable line -> nil")
}

// DangerEngine + SimpleTracker (Arshiya), see DangerChecks.swift
runDangerChecks()

// Merge-check button, see MergeChecks.swift
runMergeChecks(check)

// ThreatEngine + DangerEngine fused, see FusionChecks.swift
runFusionChecks(check)

print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
