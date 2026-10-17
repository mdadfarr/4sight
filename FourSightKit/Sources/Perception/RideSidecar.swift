import Foundation

/// The files that travel with a recorded ride: the clip itself plus `<name>.camera.json`
/// (intrinsics and lens height) and `<name>.jsonl` (GPS fixes). `tools/mcap_to_ride.py`
/// writes all three; `RideLogger` on the phone writes the clip and the jsonl.
/// Replay without these is still allowed: the pipeline falls back to f ≈ 0.9 × width
/// and speed 0, which makes the slow-vehicle rule in ThreatEngine misbehave.
public struct RideSidecar: Sendable {
    public var camera: RideCamera?
    public var track: RideTrack?

    public init(camera: RideCamera? = nil, track: RideTrack? = nil) {
        self.camera = camera
        self.track = track
    }

    /// Looks for `<clip without extension>.camera.json` and `.jsonl` next to the clip.
    public init(videoURL: URL) {
        let base = videoURL.deletingPathExtension()
        let cameraURL = base.appendingPathExtension("camera").appendingPathExtension("json")
        camera = (try? Data(contentsOf: cameraURL)).flatMap(RideCamera.init(json:))
        let gpsURL = base.appendingPathExtension("jsonl")
        track = (try? String(contentsOf: gpsURL, encoding: .utf8)).flatMap(RideTrack.init(jsonl:))
    }
}

/// Contents of `ride-*.camera.json`. Pixel units are those of the clip beside it.
public struct RideCamera: Sendable, Equatable, Decodable {
    public var f: Double
    public var u0: Double
    public var v0: Double
    public var width: Double
    public var height: Double
    /// Lens height above the road, metres. A bike mount is ~1.0; a car-roof rig is ~1.4.
    public var cameraHeight: Double?
    public var fps: Double?

    enum CodingKeys: String, CodingKey {
        case f, u0, v0, width, height, fps
        case cameraHeight = "camera_height"
    }

    public init(f: Double, u0: Double, v0: Double, width: Double, height: Double,
                cameraHeight: Double? = nil, fps: Double? = nil) {
        self.f = f; self.u0 = u0; self.v0 = v0
        self.width = width; self.height = height
        self.cameraHeight = cameraHeight; self.fps = fps
    }

    /// nil when the file has no intrinsics (the tool prints a warning and writes the rest).
    public init?(json data: Data) {
        guard let decoded = try? JSONDecoder().decode(RideCamera.self, from: data) else { return nil }
        self = decoded
    }

    /// The same camera described in the pixel units of a clip of a different size.
    public func scaled(toWidth w: Double, height h: Double) -> RideCamera {
        guard width > 0, height > 0, w > 0, h > 0 else { return self }
        let sx = w / width, sy = h / height
        return RideCamera(f: f * sx, u0: u0 * sx, v0: v0 * sy, width: w, height: h,
                          cameraHeight: cameraHeight, fps: fps)
    }
}

/// One line of `ride-*.jsonl`, the same shape `RideLogger` writes.
public struct RideFix: Sendable, Equatable, Decodable {
    public var t: Double
    public var lat: Double
    public var lon: Double
    /// Ground speed, m/s.
    public var speed: Double
    /// Degrees true, 0–360, or -1 when unknown.
    public var heading: Double

    public init(t: Double, lat: Double, lon: Double, speed: Double = 0, heading: Double = -1) {
        self.t = t; self.lat = lat; self.lon = lon; self.speed = speed; self.heading = heading
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Double.self, forKey: .t)
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 0
        heading = try c.decodeIfPresent(Double.self, forKey: .heading) ?? -1
    }
}

/// The GPS log of a ride, with `t` re-based so the first fix is at 0.
///
/// The two writers use different clocks — the tool writes seconds since the first video
/// frame, `RideLogger` writes `systemUptime` — so playback asks for a time measured from
/// the clip's own first frame and both files line up.
public struct RideTrack: Sendable, Equatable {
    /// Sorted by `t`, first fix at 0.
    public let fixes: [RideFix]
    /// The `t` of the first fix as it appeared in the file.
    public let startT: Double

    public init?(fixes: [RideFix]) {
        let sorted = fixes.sorted { $0.t < $1.t }
        guard let first = sorted.first else { return nil }
        startT = first.t
        self.fixes = sorted.map {
            RideFix(t: $0.t - first.t, lat: $0.lat, lon: $0.lon, speed: $0.speed, heading: $0.heading)
        }
    }

    /// nil when no line parses; unparseable lines on their own are skipped.
    public init?(jsonl text: String) {
        let decoder = JSONDecoder()
        var parsed: [RideFix] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let fix = try? decoder.decode(RideFix.self, from: data) else { continue }
            parsed.append(fix)
        }
        self.init(fixes: parsed)
    }

    /// The most recent fix at or before `seconds` (the first fix for times before the log starts).
    public func fix(at seconds: Double) -> RideFix? {
        guard let first = fixes.first else { return nil }
        guard seconds >= first.t else { return first }
        var lo = 0, hi = fixes.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if fixes[mid].t <= seconds { lo = mid } else { hi = mid - 1 }
        }
        return fixes[lo]
    }

    /// Seconds between the first and last fix.
    public var duration: Double { (fixes.last?.t ?? 0) - (fixes.first?.t ?? 0) }
}
