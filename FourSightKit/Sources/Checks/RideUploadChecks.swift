import Foundation
import Protocol

/// The ride upload body (docs/DATA_PIPELINE.md): privacy trim, one event per vehicle,
/// and the exact JSON keys the server parses.
func runRideUploadChecks(_ check: (Bool, String) -> Void) {
    // 1 km due north at 10 m/s, one fix a second (0.0001° of latitude ≈ 11.1 m).
    let t0 = 1_792_332_121.0
    var log = RideLog()
    for i in 0...90 { log.add(t: t0 + Double(i), lat: 43.78 + Double(i) * 0.0001, lon: -79.18, speed: 10) }
    log.add(t: t0 + 90.5, lat: 43.9, lon: -79.18, speed: 10)
    check(log.points.count == 91, "ride log: fixes closer than 1 s apart dropped")

    let kept = RideUpload.trim(log.points)
    let firstLat = kept.first?[1] ?? 0, lastLat = kept.last?[1] ?? 0
    check(kept.count == 55 && firstLat >= 43.78 + 0.0018 && lastLat <= 43.789 - 0.0018,
          "trim: first and last 200 m dropped (91 -> 55 points)")
    check(RideUpload.trim(Array(log.points.prefix(30))).isEmpty, "trim: a ride under 400 m leaves nothing")

    func event(_ t: Double, level: Int, ttc: Double? = 2.4) -> RideUpload.Event {
        RideUpload.Event(t: t0 + t, lat: 43.784, lon: -79.18, cls: .car, level: level,
                         side: "L", gapM: 0.8, ttcS: ttc, speed: 4.3)
    }
    log.add(track: 7, event(40, level: 2))
    log.add(track: 7, event(41, level: 3, ttc: nil))
    log.add(track: 7, event(42, level: 2))
    log.add(track: 9, event(50, level: 2))
    log.add(track: 9, event(51, level: 2))
    log.add(track: 4, event(45, level: 1))
    log.add(track: 5, event(3, level: 3))          // inside the trimmed start
    log.add(track: 5, event(60, level: 2))         // the same vehicle again mid-ride
    let started = Date(timeIntervalSince1970: t0), ended = Date(timeIntervalSince1970: t0 + 90)
    guard let up = log.upload(install: "6f1c0a4e", app: "4sight/1.0", demo: true, started: started, ended: ended) else {
        return check(false, "upload: a 1 km ride produced nothing")
    }
    check(up.events.map(\.t) == [t0 + 41, t0 + 50, t0 + 60] && up.events[0].level == 3,
          "dedupe: one event per track at its worst level kept; level 1 and trimmed ends dropped")

    let text = (try? up.json()).map { String(decoding: $0, as: UTF8.self) } ?? ""
    let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    let events = obj["events"] as? [[String: Any]] ?? []
    check(Set(obj.keys) == ["install", "app", "demo", "started", "ended", "points", "events"],
          "json: top-level keys exactly as the contract")
    check(obj["started"] as? String == "2026-10-18T14:02:01Z" && obj["demo"] as? Bool == true,
          "json: ISO 8601 UTC dates, demo flag")
    check(events.first.map { Set($0.keys) } == ["t", "lat", "lon", "cls", "level", "side", "gap_m", "ttc_s", "speed"],
          "json: event keys snake_case (gap_m, ttc_s)")
    check(events.first?["ttc_s"] is NSNull && events.last?["ttc_s"] as? Double == 2.4, "json: ttc_s null allowed")
    check((obj["points"] as? [[Double]])?.first?.count == 4, "json: points are [t, lat, lon, speed]")

    var empty = RideLog()
    check(empty.upload(install: "x", app: "a", demo: false, started: started, ended: ended) == nil, "empty ride: no upload")
    empty.add(track: 1, event(1, level: 3))
    check(empty.upload(install: "x", app: "a", demo: false, started: started, ended: ended) == nil,
          "ride with an event but no GPS: no upload")
}
