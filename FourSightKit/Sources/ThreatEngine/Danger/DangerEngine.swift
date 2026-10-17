// DangerEngine.swift
//
// Danger logic for the bike rear camera. A line by line port of danger.py.
// Feed it the vehicles seen in each frame; it says how strongly to vibrate
// the left and right handles.
//
// NOT compiled or run by the author (no Mac). Run DangerEngineTests.swift
// first (Cmd+U in Xcode) before relying on it.
//
// Units: pass `width`, `centerX` and `centerY` in any unit as long as
// `frameWidth` and `frameHeight` in the config use the same unit. With Vision's
// normalized boxes, set frameWidth = 1.0 and frameHeight = 1.0, and pass
// boundingBox.midX, boundingBox.width and boundingBox.midY. Vision's origin is
// the BOTTOM left, so for exclusion zones use 1 - midY as centerY.
//
// Filters applied before a detection is used:
//   too small      boxes narrower than minWidthFraction of the frame
//   exclusion zone rectangles where the bike's own parts appear
//   large + unsure a huge box with low confidence (the bike's own parts)
//   sudden jump    a box that changes size abnormally between two frames
//                  (a video cut or a tracker id swap) loses its history
// Then, per vehicle: time to collision from a line through 1 / width, a
// gentle level for close creeping vehicles, and a passing check that ignores
// vehicles far off the centre line (measured in their own widths).

import Foundation

enum AlertLevel: Int, Comparable {
    case off = 0       // nothing
    case gentle = 1    // very close and creeping toward the bike
    case warning = 2   // time to collision under ttcWarnSeconds
    case urgent = 3    // time to collision under ttcUrgentSeconds

    static func < (a: AlertLevel, b: AlertLevel) -> Bool { a.rawValue < b.rawValue }
}

/// A rectangle as fractions of the frame, 0 to 1.
struct ExclusionZone {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
}

struct DangerConfig {
    var frameWidth: Double = 640
    var frameHeight: Double = 360          // only needed for exclusion zones
    var windowSeconds: Double = 0.5        // how far back the trend line looks
    var minSamples: Int = 5                // frames needed inside the window
    var minSpanSeconds: Double = 0.1
    var ttcWarnSeconds: Double = 3.0
    var ttcUrgentSeconds: Double = 2.0
    var closeFraction: Double = 0.6        // box wider than this fraction of the frame = very close
    var minGrowthPerSecond: Double = 0.01  // below 1% of frame width per second = not growing
    var holdSeconds: Double = 1.0          // keep an alert on this long after the danger passes
    var dropTrackAfterSeconds: Double = 1.0
    var mirror: Bool = true                // rear camera: image left is the rider's right

    var minWidthFraction: Double = 0.04    // ignore boxes narrower than this fraction of the frame
    var largeFraction: Double = 0.5        // a box at least this wide counts as "large"...
    var largeMinConfidence: Double = 0.5   // ...and is ignored unless the detector is at least this sure
    var jumpRatio: Double = 1.6            // size change between two frames beyond this = reset
    var maxLateralWidths: Double = 1.0     // off centre by more than this many vehicle widths = passing by
    var exclusionZones: [ExclusionZone] = []
}

struct Detection {
    var trackID: Int          // from SimpleTracker; negative means "no id", ignored
    var centerX: Double
    var width: Double
    var centerY: Double? = nil    // only needed for exclusion zones
    var confidence: Double = 1.0  // detector confidence, 0 to 1
}

enum Side { case left, right, both }   // from the rider's point of view

struct Assessment {
    var trackID: Int
    var level: AlertLevel
    var ttcSeconds: Double?
    var growthPerSecond: Double
    var widthFraction: Double
    var side: Side
}

struct DangerOutput {
    var left: AlertLevel = .off
    var right: AlertLevel = .off
    var vehicles: [Assessment] = []   // only vehicles with level above .off
}

typealias Point = (t: Double, w: Double)
typealias Sample = (t: Double, w: Double, cx: Double)

/// Least squares line through (time, value) points.
/// Returns the slope and the fitted value at the latest point.
func fitLine(_ points: [Point]) -> (slope: Double, fittedLast: Double) {
    guard let t0 = points.first?.t else { return (slope: 0, fittedLast: 0) }
    let n = Double(points.count)
    let ts = points.map { $0.t - t0 }
    let ws = points.map { $0.w }
    let meanT = ts.reduce(0, +) / n
    let meanW = ws.reduce(0, +) / n
    var sxx = 0.0
    var sxy = 0.0
    for i in 0..<points.count {
        sxx += (ts[i] - meanT) * (ts[i] - meanT)
        sxy += (ts[i] - meanT) * (ws[i] - meanW)
    }
    if sxx == 0 { return (slope: 0, fittedLast: ws[ws.count - 1]) }
    let slope = sxy / sxx
    return (slope: slope, fittedLast: meanW + slope * (ts[ts.count - 1] - meanT))
}

final class DangerEngine {
    let config: DangerConfig
    private var samples: [Int: [Sample]] = [:]
    private var lastSeen: [Int: Double] = [:]
    private var heldLeft: (level: AlertLevel, until: Double) = (level: .off, until: -1)
    private var heldRight: (level: AlertLevel, until: Double) = (level: .off, until: -1)

    init(config: DangerConfig = DangerConfig()) {
        self.config = config
    }

    /// Process one frame. Call it every frame, even when nothing was detected.
    /// `time` is in seconds (for example the frame's presentation timestamp).
    func update(time t: Double, detections: [Detection]) -> DangerOutput {
        var instLeft = AlertLevel.off
        var instRight = AlertLevel.off
        var vehicles: [Assessment] = []

        for det in detections where det.trackID >= 0 {
            if isIgnored(det) { continue }
            let widthFraction = det.width / config.frameWidth
            var buf = samples[det.trackID] ?? []
            if let prev = buf.last, prev.w > 0 {
                let ratio = widthFraction / prev.w
                if ratio > config.jumpRatio || ratio < 1.0 / config.jumpRatio {
                    buf.removeAll()   // video cut or id swap: start this vehicle's history again
                }
            }
            buf.append((t: t, w: widthFraction, cx: det.centerX / config.frameWidth))
            buf.removeAll { $0.t < t - 1.0 }
            samples[det.trackID] = buf
            lastSeen[det.trackID] = t

            let a = assess(det, buf, at: t)
            if a.level != .off {
                vehicles.append(a)
                if a.side == .left || a.side == .both { instLeft = max(instLeft, a.level) }
                if a.side == .right || a.side == .both { instRight = max(instRight, a.level) }
            }
        }

        // forget vehicles not seen for a while
        let stale = lastSeen.filter { t - $0.value > config.dropTrackAfterSeconds }.map { $0.key }
        for id in stale {
            samples[id] = nil
            lastSeen[id] = nil
        }

        let left = applyHold(instLeft, held: &heldLeft, at: t)
        let right = applyHold(instRight, held: &heldRight, at: t)
        return DangerOutput(left: left, right: right, vehicles: vehicles)
    }

    private func isIgnored(_ det: Detection) -> Bool {
        let widthFraction = det.width / config.frameWidth
        if widthFraction < config.minWidthFraction { return true }   // too small and far to measure
        if widthFraction >= config.largeFraction && det.confidence < config.largeMinConfidence {
            return true   // huge but unsure: probably the bike's own parts
        }
        if let cy = det.centerY {
            let fx = det.centerX / config.frameWidth
            let fy = cy / config.frameHeight
            for z in config.exclusionZones where fx >= z.x1 && fx <= z.x2 && fy >= z.y1 && fy <= z.y2 {
                return true
            }
        }
        return false
    }

    private func applyHold(_ inst: AlertLevel,
                           held: inout (level: AlertLevel, until: Double),
                           at t: Double) -> AlertLevel {
        var level = held.level
        if t >= held.until { level = .off }
        if inst != .off && inst >= level {
            level = inst
            held = (level: inst, until: t + config.holdSeconds)   // refresh the hold
        }
        return max(inst, level)
    }

    private func assess(_ det: Detection, _ buf: [Sample], at t: Double) -> Assessment {
        let window = buf.filter { $0.t >= t - config.windowSeconds - 1e-9 }
        let widthFraction = window.last?.w ?? 0
        let side = sideFor(centerX: det.centerX)

        guard window.count >= config.minSamples,
              let first = window.first,
              let last = window.last,
              last.t - first.t >= config.minSpanSeconds else {
            return Assessment(trackID: det.trackID, level: .off, ttcSeconds: nil,
                              growthPerSecond: 0, widthFraction: widthFraction, side: side)
        }

        let widthPoints: [Point] = window.map { (t: $0.t, w: $0.w) }
        let line = fitLine(widthPoints)
        let growing = line.slope >= config.minGrowthPerSecond && line.fittedLast > 0

        // Time to collision from a line through 1 / width. For a vehicle closing
        // at constant speed this is exact; a line through width itself would
        // overestimate by about half the window.
        var ttc: Double? = nil
        if growing && window.allSatisfy({ $0.w > 0 }) {
            let inversePoints: [Point] = window.map { (t: $0.t, w: 1.0 / $0.w) }
            let inv = fitLine(inversePoints)
            if inv.slope < 0 && inv.fittedLast > 0 {
                ttc = inv.fittedLast / -inv.slope
            }
        }

        var level = AlertLevel.off
        if let ttc = ttc {
            if ttc < config.ttcUrgentSeconds {
                level = .urgent
            } else if ttc < config.ttcWarnSeconds {
                level = .warning
            }
        }
        if level == .off && growing && line.fittedLast >= config.closeFraction {
            level = .gentle
        }

        // Passing check: far off the centre line, measured in the vehicle's own
        // widths, means it will go past the bike, not into it. Uses the latest
        // position so a car sliding sideways is caught quickly.
        let lateralWidths = abs(last.cx - 0.5) / max(line.fittedLast, 1e-6)
        if lateralWidths > config.maxLateralWidths {
            level = .off
        }

        return Assessment(trackID: det.trackID, level: level, ttcSeconds: ttc,
                          growthPerSecond: line.slope, widthFraction: line.fittedLast, side: side)
    }

    private func sideFor(centerX: Double) -> Side {
        let frac = centerX / config.frameWidth
        if frac >= 1.0 / 3.0 && frac <= 2.0 / 3.0 { return .both }   // directly behind
        let imageLeft = frac < 1.0 / 3.0
        if imageLeft { return config.mirror ? .right : .left }
        return config.mirror ? .left : .right
    }
}
