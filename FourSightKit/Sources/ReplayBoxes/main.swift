import Foundation
import Perception
import Protocol

// Replays a Python boxes csv (frame,track_id,class,conf,x1,y1,x2,y2,...) through our
// DetectionFilter + Tracker, ignoring track_id, and prints how fragmented our ids are.
// usage: swift run ReplayBoxes <boxes.csv> [stride=2]   (stride 2 turns 20 fps into our 10 fps)
let args = CommandLine.arguments
guard args.count >= 2, let text = try? String(contentsOfFile: args[1], encoding: .utf8) else {
    print("usage: ReplayBoxes <boxes.csv> [stride]"); exit(2)
}
let stride = args.count > 2 ? Double(args[2]) ?? 2 : 2   // may be fractional: 1.5 turns 30 fps into 20 Hz
var lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: ",", omittingEmptySubsequences: false) }
let header = lines.removeFirst().map(String.init)
func col(_ name: String) -> Int { header.firstIndex(of: name)! }
let (fF, fCls, fConf, fX1, fY1, fX2, fY2) = (col("frame"), col("class"), col("conf"), col("x1"), col("y1"), col("x2"), col("y2"))
let fps = Double(lines[0][col("fps")]) ?? 10
let imageW = Double(lines[0][col("frame_w")]) ?? 1280, imageH = Double(lines[0][col("frame_h")]) ?? 720

var byFrame: [Int: [Detection]] = [:]
for l in lines where l.count == header.count {
    guard let fr = Int(l[fF]), let conf = Double(l[fConf]), let x1 = Double(l[fX1]), let y1 = Double(l[fY1]),
          let x2 = Double(l[fX2]), let y2 = Double(l[fY2]) else { continue }
    let cls = VehicleClass(rawValue: String(l[fCls])) ?? .car
    byFrame[fr, default: []].append(Detection(box: Box(x: x1, y: y1, w: x2 - x1, h: y2 - y1), cls: cls, confidence: conf))
}
let frames = byFrame.keys.sorted()
let tracker = Tracker()
let filter = DetectionFilter()
let hz = fps / stride
tracker.maxMisses = Int((1.5 * hz).rounded())   // the app keeps a lost track 1.5 s at any rate
tracker.minHits = max(2, Int((0.2 * hz).rounded()))   // and confirms on 0.2 s of sightings
var ego = EgoMask()
var lifetime: [Int: Int] = [:]   // frames with a real hit (coasting excluded)
var birth: [Int: (Int, Box)] = [:]
for k in 0... {
    let fr = frames.first! + Int((Double(k) * stride).rounded())
    if fr > frames.last! { break }
    let dets = ego.apply(filter.apply(byFrame[fr] ?? [], imageW: imageW, imageH: imageH),
                         imageW: imageW, imageH: imageH, t: Double(fr) / fps)
    for t in tracker.update(detections: dets, dt: stride / fps) where t.misses == 0 {
        lifetime[t.id, default: 0] += 1
        if birth[t.id] == nil { birth[t.id] = (fr, t.box) }
    }
}
let lives = lifetime.values.sorted()
if ProcessInfo.processInfo.environment["VERBOSE"] != nil {
    for (id, b) in birth.sorted(by: { $0.key < $1.key }) {
        print(String(format: "id=%d born=%d hits=%d box=%.0f,%.0f %.0fx%.0f", id, b.0, lifetime[id]!, b.1.x, b.1.y, b.1.w, b.1.h))
    }
}
print("frames=\(frames.count) stride=\(stride) confirmed_ids=\(lives.count) allocated=\(tracker.allocatedIDs) median_life=\(lives.isEmpty ? 0 : lives[lives.count / 2]) max_life=\(lives.last ?? 0)")
// Seconds, so different rates compare: how long a confirmed track lives, and how many
// flicker in for under half a second (the ghosts and duplicates a rider sees).
let secs = lives.map { Double($0) / hz }
print(String(format: "rate=%.0fHz confirmed=%d median_life=%.2fs short(<0.5s)=%d long(>3s)=%d",
             hz, lives.count, secs.isEmpty ? 0 : secs[secs.count / 2],
             secs.filter { $0 < 0.5 }.count, secs.filter { $0 > 3 }.count))
