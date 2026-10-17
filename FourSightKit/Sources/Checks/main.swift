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
    check(run(e, car(-0.8), frames: 1, from: 2)?.level == 1, "alert once")
    let imm = TrackState(id: 1, cls: .car, z: 10, gap: -0.5, invTTC: 1)
    check(run(e, imm, frames: 1, from: 3)?.level == 3, "escalation to 3 allowed once")
    check(run(e, imm, frames: 1, from: 4)?.level == 1, "no second escalation")
}
check(run(ThreatEngine(), car(-1.2), frames: 10)?.level == 1, "1.2 m -> caution only")
check(run(ThreatEngine(), car(-2.0), frames: 10)?.level == 0, "2.0 m -> level 0")
check(run(ThreatEngine(), car(-1.3, cls: .bus), frames: 4)?.level == 2, "bus 1.3 m -> threat")
check(run(ThreatEngine(), TrackState(id: 1, cls: .car, z: 10, gap: -0.5, invTTC: 1), frames: 4)?.level == 3, "aReq 5 -> imminent")
check(run(ThreatEngine(), TrackState(id: 1, cls: .car, z: 10, gap: -0.5, invTTC: 0), frames: 10)?.level == 0, "parked car silent")
check(run(ThreatEngine(), TrackState(id: 1, cls: .car, z: 5, gap: -1.2, invTTC: 0.1), frames: 10, speed: 1)?.level == 0, "slow vehicle: no caution")
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
}

// TTC
do {
    let est = TTCEstimator(); let T = 10.0; var t = 0.0; var r: Double?
    while t < 4 { let s = 100 / (T - t); r = est.update(id: 1, box: Box(x: 0, y: 0, w: s, h: s), t: t, touchesEdge: false); t += 1 / 30 }
    let truth = 1 / (T - (t - 1 / 30))
    check(r != nil && near(r!, truth, truth * 0.15), "invTTC \(r ?? -1) vs \(truth) within 15%")
}

// Gap
do {
    let est = GapEstimator(f: 1000, u0: 640, v0: 360, imageW: 1280, imageH: 720)
    check(near(est.gap(box: Box(x: 700, y: 300, w: 200, h: 100), cls: .car, z: 20), -1.47, 1e-9), "gap geometry un-mirrored -> -1.47")
    check(near(est.range(box: Box(x: 0, y: 310, w: 90, h: 100), cls: .car), 20, 1e-9), "ground-plane range 20 m")
    check(near(est.range(box: Box(x: 0, y: 620, w: 90, h: 100), cls: .car), 20, 1e-9), "width fallback 20 m")
}

// DangerEngine + SimpleTracker (Arshiya), see DangerChecks.swift
runDangerChecks()

print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
