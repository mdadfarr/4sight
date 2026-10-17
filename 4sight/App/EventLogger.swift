import Foundation
import Protocol
import ThreatEngine
import os

/// Appends one JSON line per near-miss episode to Documents/events.jsonl (no rider identity).
/// An episode is (track id, level >= 2 first reached); a 2 -> 3 escalation writes a second line.
nonisolated final class EventLogger: @unchecked Sendable {
    static let shared = EventLogger()
    static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("events.jsonl")

    private struct State {
        var handle: FileHandle?
        var count = 0
        var fix: (lat: Double, lon: Double)?
        /// Highest level already written per track id; pruned to the tracks still decided on.
        var written: [Int: Int] = [:]
    }

    private let state: OSAllocatedUnfairLock<State>
    private let iso = ISO8601DateFormatter()

    private init() {
        let path = Self.url.path
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        let existing = (try? String(contentsOfFile: path, encoding: .utf8))?.split(separator: "\n").count ?? 0
        let h = try? FileHandle(forWritingTo: Self.url)
        _ = try? h?.seekToEnd()
        state = OSAllocatedUnfairLock(initialState: State(handle: h, count: existing))
    }

    var count: Int { state.withLock { $0.count } }

    /// Latest GPS fix; nil until the first one, in which case lat/lon are written as null.
    func setFix(lat: Double, lon: Double) { state.withLock { $0.fix = (lat, lon) } }

    func record(decisions: [Decision], states tracks: [TrackState], input: RearInputs) {
        let states = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        state.withLock { s in
            for d in decisions where d.level >= 2 && d.level > s.written[d.id] ?? 0 {
                s.written[d.id] = d.level
                let tr = states[d.id]
                let rec: [String: Any] = [
                    "timestamp": iso.string(from: Date()),
                    "lat": s.fix?.lat ?? NSNull(), "lon": s.fix?.lon ?? NSNull(),
                    "speed": input.speed, "heading": input.heading,
                    "left_level": d.grip == "L" ? d.level : 0, "right_level": d.grip == "R" ? d.level : 0,
                    "ttc_seconds": (tr?.invTTC ?? 0) > 0 ? 1 / tr!.invTTC : NSNull(),
                    "gap_m": d.gapPred, "cls": tr?.cls.rawValue ?? "unknown",
                    "engine": "fused", "track_id": d.id, "demo": input.demo,
                ]
                guard let data = try? JSONSerialization.data(withJSONObject: rec), let h = s.handle else { continue }
                h.write(data + Data("\n".utf8))
                try? h.synchronize()
                s.count += 1
            }
            let live = Set(decisions.map(\.id))
            s.written = s.written.filter { live.contains($0.key) }
        }
    }
}
