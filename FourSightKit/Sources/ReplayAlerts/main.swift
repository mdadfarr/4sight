import Foundation
import Perception
import Protocol
import ThreatEngine

// Replays a boxes csv (frame,class,conf,x1,y1,x2,y2 + fps,frame_w,frame_h columns, as
// ml/detect_video.py writes) through the rear phone's whole decision chain, the same
// classes and constants RearWorker uses, and prints when the grips would have buzzed.
// usage: swift run ReplayAlerts <boxes.csv> [hz=10] [f=900]   F=.. DEMO=0 env overrides
let args = CommandLine.arguments
guard args.count >= 2, let text = try? String(contentsOfFile: args[1], encoding: .utf8) else {
    print("usage: ReplayAlerts <boxes.csv> [hz] [f_px]"); exit(2)
}
let hz = args.count > 2 ? Double(args[2]) ?? 10 : 10
let env = ProcessInfo.processInfo.environment
let demo = env["DEMO"] != "0"
var lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: ",", omittingEmptySubsequences: false) }
let header = lines.removeFirst().map(String.init)
func col(_ name: String) -> Int { header.firstIndex(of: name)! }
let (fF, fCls, fConf, fX1, fY1, fX2, fY2) = (col("frame"), col("class"), col("conf"), col("x1"), col("y1"), col("x2"), col("y2"))
let fps = Double(lines[0][col("fps")]) ?? 30
let imageW = Double(lines[0][col("frame_w")]) ?? 720, imageH = Double(lines[0][col("frame_h")]) ?? 1280
let f = args.count > 3 ? Double(args[3]) ?? 900 : 900

var byFrame: [Int: [Detection]] = [:]
var lastFrame = 0
for l in lines where l.count == header.count {
    guard let fr = Int(l[fF]), let conf = Double(l[fConf]), let x1 = Double(l[fX1]), let y1 = Double(l[fY1]),
          let x2 = Double(l[fX2]), let y2 = Double(l[fY2]), let cls = VehicleClass(rawValue: String(l[fCls])) else { continue }
    byFrame[fr, default: []].append(Detection(box: Box(x: x1, y: y1, w: x2 - x1, h: y2 - y1), cls: cls, confidence: conf))
    lastFrame = max(lastFrame, fr)
}

// RearWorker's chain, with its retime() constants for this rate.
let stride = fps / hz
var filter = DetectionFilter()
var ego = EgoMask()
let tracker = Tracker()
tracker.maxMisses = Int((1.5 * hz).rounded())
tracker.minHits = max(2, Int((0.2 * hz).rounded()))
let ttc = TTCEstimator()
let rangeFilter = RangeFilter()
let engine = ThreatEngine()
engine.config.debounceFrames = max(2, Int((0.4 * hz).rounded()))
engine.config.corroboratedDebounceFrames = max(1, Int((0.2 * hz).rounded()))
var dangerConfig = DangerConfig()
dangerConfig.frameWidth = 1; dangerConfig.frameHeight = 1; dangerConfig.mirror = true
let danger = DangerEngine(config: dangerConfig)
var geo = GapEstimator(f: f, u0: imageW / 2, v0: imageH / 2, cameraHeight: 1.0, imageW: imageW, imageH: imageH)
geo.cameraOffset = 0.10
var lastGap: [Int: (gap: Double, t: Double, v: Double)] = [:]
var sentLevel: [Int: (grip: String, level: Int)] = [:]
var seenIDs = Set<Int>()
var buzzes: [(t: Double, cmd: String, id: Int, cls: String, z: Double, ttc: Double)] = []
var perSecond: [Int: (ids: Set<Int>, born: Int, maxH: Double, boxes: Int)] = [:]

func gapVelocity(id: Int, gap: Double, t: Double) -> Double {
    var v = 0.0
    if let prev = lastGap[id], t - prev.t > 0.01 { v = prev.v + 0.3 * ((gap - prev.gap) / (t - prev.t) - prev.v) }
    lastGap[id] = (gap, t, v)
    return v
}

var k = 0
while true {
    let fr = Int((Double(k) * stride).rounded()); k += 1
    if fr > lastFrame { break }
    let t = Double(fr) / fps
    let dets = ego.apply(filter.apply(byFrame[fr] ?? [], imageW: imageW, imageH: imageH), imageW: imageW, imageH: imageH, t: t)
    let tracks = tracker.update(detections: dets, dt: 1 / hz)
    for tr in tracks where filter.jumped(id: tr.id, box: tr.box, imageW: imageW) {
        ttc.reset(id: tr.id); rangeFilter.reset(id: tr.id); lastGap[tr.id] = nil
    }
    filter.forget(except: Set(tracks.map(\.id)))
    let states: [TrackState] = tracks.map { tr in
        let z = rangeFilter.update(id: tr.id, z: geo.range(box: tr.box, cls: tr.cls), t: t)
        let gap = geo.gap(box: tr.box, cls: tr.cls, z: z)
        let inv = ttc.update(id: tr.id, box: tr.box, t: t, touchesEdge: tr.box.touchesEdge(imageW: imageW, imageH: imageH)) ?? 0
        return TrackState(id: tr.id, cls: tr.cls, z: z, gap: gap, gapVelocity: gapVelocity(id: tr.id, gap: gap, t: t),
                          invTTC: inv, turnR: false, framesSeen: tr.hits)
    }
    lastGap = lastGap.filter { k, _ in tracks.contains { $0.id == k } }
    let out = danger.update(time: t, detections: tracks.map {
        DangerDetection(trackID: $0.id, centerX: $0.box.cx / imageW, width: $0.box.w / imageW, centerY: $0.box.cy / imageH, confidence: 1)
    })
    let votes = Dictionary(out.vehicles.map { ($0.trackID, DangerVote(level: $0.level, side: $0.side)) }, uniquingKeysWith: { a, _ in a })
    let threat = engine.update(tracks: states, bikeSpeed: 0, demoMode: demo, now: t, corroborated: Fusion.corroborated(votes))
    let decisions = Fusion.fuse(threat, votes: votes, states: states)
    let byID = Dictionary(states.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    // driveHaptics, verbatim in effect.
    let hadAlert = sentLevel.values.contains { $0.level >= 2 }
    for d in decisions where d.level >= 2 {
        if let prev = sentLevel[d.id], prev.grip == d.grip, prev.level >= d.level { continue }
        sentLevel[d.id] = (d.grip, d.level)
        let s = byID[d.id]
        buzzes.append((t, "\(d.grip)\(d.level)", d.id, s?.cls.rawValue ?? "?", s?.z ?? 0, (s?.invTTC ?? 0) > 0 ? 1 / s!.invTTC : .infinity))
    }
    let present = Set(tracks.map(\.id)), holding = Set(decisions.map(\.id))
    sentLevel = sentLevel.filter { present.contains($0.key) || holding.contains($0.key) }
    if hadAlert, !sentLevel.values.contains(where: { $0.level >= 2 }) { buzzes.append((t, "X", 0, "", 0, 0)) }

    let sec = Int(t)
    var p = perSecond[sec] ?? ([], 0, 0, 0)
    for tr in tracks where tr.misses == 0 {
        p.ids.insert(tr.id); p.maxH = max(p.maxH, tr.box.h / imageH)
        if !seenIDs.contains(tr.id) { seenIDs.insert(tr.id); p.born += 1 }
    }
    p.boxes += dets.count
    perSecond[sec] = p
    if env["VERBOSE"] != nil {
        for s in states {
            let d = decisions.first { $0.id == s.id }
            print(String(format: "t=%.2f id=%d %@ z=%.1f gap=%.2f invTTC=%.3f lvl=%d hits=%d danger=%@", t, s.id, s.cls.rawValue, s.z, s.gap, s.invTTC, d?.level ?? 0, s.framesSeen, votes[s.id].map { "\($0.level)" } ?? "-"))
        }
    }
}

print("clip \(String(format: "%.0f", Double(lastFrame) / fps)) s at \(Int(fps)) fps, replayed at \(Int(hz)) Hz, f=\(Int(f)) px, demo=\(demo)")
print("per second: ids seen | new ids | tallest box (frame fraction)")
for sec in perSecond.keys.sorted() {
    let p = perSecond[sec]!
    let b = buzzes.filter { Int($0.t) == sec }.map { $0.cmd == "X" ? "X" : "\($0.cmd)#\($0.id)" }.joined(separator: " ")
    print(String(format: "%4ds  %@  +%d  h=%.2f  %@", sec, p.ids.sorted().map(String.init).joined(separator: ","), p.born, p.maxH, b))
}
print("buzzes:")
for b in buzzes where b.cmd != "X" {
    print(String(format: "  t=%6.2f %@ id=%d %@ z=%.1f ttc=%.1f", b.t, b.cmd, b.id, b.cls, b.z, b.ttc))
}
print("total ids=\(seenIDs.count) buzzes=\(buzzes.filter { $0.cmd != "X" }.count)")
