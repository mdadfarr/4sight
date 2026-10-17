import CoreLocation
import Foundation

/// Every ride's GPS track, always on while the rear camera runs (video stays opt-in, it is
/// the part that fills the phone): Documents/gps-<stamp>.jsonl, one fix per line,
/// {"t","time","lat","lon","speed","heading","acc"}. `t` is host uptime, the camera's
/// clock, so a track lines up with events and any video from the same ride.
/// Nothing identifies the rider; it leaves the phone only when shared.
nonisolated final class GPSLog: @unchecked Sendable {
    private let handle: FileHandle?
    private let iso = ISO8601DateFormatter()
    private let queue = DispatchQueue(label: "foursight.gpslog")

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = docs.appendingPathComponent("gps-\(stamp).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    deinit { try? handle?.close() }

    func append(_ loc: CLLocation) {
        let line = String(format: "{\"t\":%.3f,\"time\":\"%@\",\"lat\":%.6f,\"lon\":%.6f,\"speed\":%.2f,\"heading\":%.1f,\"acc\":%.1f}\n",
                          ProcessInfo.processInfo.systemUptime, iso.string(from: loc.timestamp),
                          loc.coordinate.latitude, loc.coordinate.longitude,
                          max(loc.speed, 0), loc.course >= 0 ? loc.course : -1, loc.horizontalAccuracy)
        queue.async { [handle] in handle?.write(Data(line.utf8)) }
    }

    /// Every file a website import wants: all GPS tracks and the near-miss events.
    static var shareable: [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("gps-") && $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } + [EventLogger.url]
    }
}
