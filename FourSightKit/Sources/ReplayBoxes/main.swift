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
let stride = args.count > 2 ? Int(args[2]) ?? 2 : 2
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
var lifetime: [Int: Int] = [:]   // frames with a real hit (coasting excluded)
var birth: [Int: (Int, Box)] = [:]
for fr in Swift.stride(from: frames.first!, through: frames.last!, by: stride) {
    let dets = filter.apply(byFrame[fr] ?? [], imageW: imageW, imageH: imageH)
    for t in tracker.update(detections: dets, dt: Double(stride) / fps) where t.misses == 0 {
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
