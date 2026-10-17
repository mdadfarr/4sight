import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Links
import Perception
import Protocol
import ThreatEngine
import os

/// Box in normalised buffer coordinates (top-left origin) for the preview overlay.
nonisolated struct OverlayTrack: Sendable, Identifiable {
    let id: Int
    let cls: VehicleClass
    let rect: CGRect
    let level: Int
    /// Metres behind, as the engine sees it.
    let z: Double
}

nonisolated struct RearSnapshot: @unchecked Sendable {
    var message: FrameMessage
    var overlay: [OverlayTrack]
    var inferenceMs: Double
    var benchMs: Double
    var peer: PeerLink.Rear.State
    var previewImage: CGImage?
    /// Focal length in pixels the range maths is using, and whether it came from the lens
    /// (delivered intrinsics) or the 0.9 x long-side guess. Shown so a bad distance can be traced.
    var focal: Double
    var focalFromLens: Bool
}

/// Which decision engine runs: metric ThreatEngine (default) or Arshiya's frame-fraction DangerEngine.
nonisolated enum Engine: String, Sendable { case threat, danger }

/// Sensor values the main actor pushes in; read once per frame.
nonisolated struct RearInputs: Sendable {
    var engine: Engine = .threat
    var speed = 0.0
    var heading = -1.0
    var yaw: Double?
    var demo = false
    var thermal: ThermalLabel = .nominal
    var logging = false
    var exclusionZones: [DetectionFilter.Zone] = []
}

/// Everything off the main actor: capture → detect → track → TTC/gap → ThreatEngine → links.
nonisolated final class RearWorker: @unchecked Sendable {
    static let detectionHz = 10.0
    static let cameraHeight = 1.0

    let inputs = OSAllocatedUnfairLock(initialState: RearInputs())
    let source: CaptureSource
    let peer = PeerLink.Rear()
    private let detector: Detector
    private var filter = DetectionFilter()
    private let tracker = Tracker()
    private let ttc = TTCEstimator()
    private let rangeFilter = RangeFilter()
    private let engine = ThreatEngine()
    private let danger = DangerAdapter()
    /// The last frame's tracks, read from the Bluetooth queue when a button is pressed.
    private struct LatestView { var states: [TrackState] = []; var t = 0.0; var wall = Date.distantPast }
    private let latest = OSAllocatedUnfairLock(initialState: LatestView())
    /// The merge answer to attach to outgoing frames, until it ages out.
    private let lastMerge = OSAllocatedUnfairLock<MergeMessage?>(initialState: nil)
    private let sendHaptic: @Sendable (BLECommand) -> Void
    private let publish: @Sendable (RearSnapshot) -> Void
    private let wantsPreviewImage: Bool
    private let ciContext = CIContext()
    private var task: Task<Void, Never>?
    private var logger: RideLogger?

    private var gapEstimator: GapEstimator?
    private var geoFromIntrinsics = false
    private var lastDetectT = -Double.infinity
    private var lastSendT = -Double.infinity
    private var lastGap: [Int: (gap: Double, t: Double, v: Double)] = [:]
    private var yawRef: Double?
    private var yawRefT = 0.0
    private var frameTimes: [Double] = []
    private var bench: [(t: Double, ms: Double)] = []
    /// Highest level ever sent to the grips per track id; drives the "send on change" rule.
    private var sentLevel: [Int: (grip: String, level: Int)] = [:]

    // Pipeline instrumentation (`log stream --predicate 'subsystem == "com.zupersun.foursight"'`).
    private static let log = Logger(subsystem: "com.zupersun.foursight", category: "pipeline")
    private var wallStart: Date?
    private var firstPTS = 0.0
    private var lastFrameT = -Double.infinity
    private var minGap = Double.infinity
    private var dropped = 0
    private var stat = (count: 0, ms: [Double](), maxLag: 0.0, since: 0.0)

    init(source: CaptureSource, previewImage: Bool,
         sendHaptic: @escaping @Sendable (BLECommand) -> Void,
         publish: @escaping @Sendable (RearSnapshot) -> Void) throws {
        self.source = source
        self.wantsPreviewImage = previewImage
        self.sendHaptic = sendHaptic
        self.publish = publish
        detector = try Detector()
    }

    func start() throws {
        peer.start()
        try source.start()
        task = Task.detached(priority: .userInitiated) { [self] in
            for await frame in source.frames {
                if Task.isCancelled { break }
                process(frame)
            }
        }
    }

    func stop() {
        task?.cancel()
        source.stop()
        peer.stop()
        logger?.finish()
        logger = nil
    }

    func logLocation(_ line: String) { logger?.append(line) }

    private func process(_ frame: CapturedFrame) {
        let input = inputs.withLock { $0 }
        let t = frame.timestamp
        syncLogger(on: input.logging, frame: frame)
        if wallStart == nil { wallStart = Date(); firstPTS = t; stat.since = t }
        if lastFrameT.isFinite {   // gaps larger than the source cadence = frames the stream buffer dropped
            let gap = t - lastFrameT
            minGap = min(minGap, gap)
            if gap > 1.5 * minGap { dropped += Int((gap / minGap).rounded()) - 1 }
        }
        lastFrameT = t

        let hz = input.thermal == .serious || input.thermal == .critical ? 5.0 : Self.detectionHz
        guard t - lastDetectT >= 1 / hz - 0.001 else { return }
        let dt = lastDetectT.isFinite ? t - lastDetectT : 1 / hz
        lastDetectT = t

        let w = Double(CVPixelBufferGetWidth(frame.pixelBuffer))
        let h = Double(CVPixelBufferGetHeight(frame.pixelBuffer))
        // Rebuilt when the frame changes shape too: turning the phone turns the frames upright.
        let reshaped = gapEstimator.map { $0.imageW != w || $0.imageH != h } ?? true
        if reshaped || (frame.intrinsics != nil && !geoFromIntrinsics) {
            geoFromIntrinsics = frame.intrinsics != nil
            gapEstimator = GapEstimator(f: frame.intrinsics?.fx ?? 0.9 * max(w, h), u0: frame.intrinsics?.cx ?? w / 2,
                                        v0: frame.intrinsics?.cy ?? h / 2,
                                        cameraHeight: frame.cameraHeight ?? Self.cameraHeight,
                                        imageW: w, imageH: h)
        }
        let geo = gapEstimator!

        let t0 = ContinuousClock.now
        filter.exclusionZones = input.exclusionZones
        let detections = filter.apply(detector.detect(frame.pixelBuffer), imageW: w, imageH: h)
        let took = (ContinuousClock.now - t0).components
        let ms = Double(took.seconds) * 1000 + Double(took.attoseconds) / 1e15
        let tracks = tracker.update(detections: detections, dt: dt)
        for tr in tracks where filter.jumped(id: tr.id, box: tr.box, imageW: w) {
            ttc.reset(id: tr.id); rangeFilter.reset(id: tr.id); lastGap[tr.id] = nil   // size jump: history is from another vehicle or a cut
        }
        filter.forget(except: Set(tracks.map(\.id)))
        // Draw and send only what was detected in the last 0.2 s. The tracker keeps a lost
        // track alive 1.5 s so its id survives a dropout, but its box is then a drifting guess;
        // shown, it reads as a second box beside the real one. The engine still sees it.
        let visible = Set(tracks.filter { $0.misses <= 2 }.map(\.id))

        let yawCorrection = headingDelta(yaw: input.yaw, t: t)
        let states: [TrackState] = tracks.map { tr in
            let z = rangeFilter.update(id: tr.id, z: geo.range(box: tr.box, cls: tr.cls), t: t)
            var gap = geo.gap(box: tr.box, cls: tr.cls, z: z)
            gap -= geo.headingCorrection(deltaHeadingRad: yawCorrection, z: z)
            let inv = ttc.update(id: tr.id, box: tr.box, t: t,
                                 touchesEdge: tr.box.touchesEdge(imageW: w, imageH: h)) ?? 0
            return TrackState(id: tr.id, cls: tr.cls, z: z, gap: gap, gapVelocity: gapVelocity(id: tr.id, gap: gap, t: t),
                              invTTC: inv, turnR: false, framesSeen: tr.hits)
        }
        lastGap = lastGap.filter { k, _ in tracks.contains { $0.id == k } }

        let decisions: [Decision], gripDecisions: [Decision]
        if input.engine == .danger {
            let gaps = Dictionary(states.map { ($0.id, $0.gap) }, uniquingKeysWith: { a, _ in a })
            (decisions, gripDecisions) = danger.update(tracks: tracks, gaps: gaps, t: t, imageW: w, imageH: h)
        } else {
            decisions = engine.update(tracks: states, bikeSpeed: input.speed, demoMode: input.demo, now: t)
            gripDecisions = decisions
        }
        latest.withLock { $0 = LatestView(states: states, t: t, wall: Date()) }
        let byID = Dictionary(decisions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        driveHaptics(decisions: gripDecisions, present: Set(tracks.map(\.id)))
        EventLogger.shared.record(decisions: decisions, states: states, input: input)

        let lag = Date().timeIntervalSince(wallStart!) - (t - firstPTS)
        let ids = tracks.map { String($0.id) }.joined(separator: ",")
        Self.log.log("\(String(format: "frame pts=%.2f lag=%.3f inf=%.1fms tracks=%d ids=%@", t, lag, ms, tracks.count, ids), privacy: .public)")
        let stateByID = Dictionary(states.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for s in states {
            let d = byID[s.id]
            Self.log.log("\(String(format: "track pts=%.2f id=%d cls=%@ z=%.1f gap=%.2f gapV=%.2f invTTC=%.3f level=%d gapPred=%.2f", t, s.id, s.cls.rawValue, s.z, s.gap, s.gapVelocity, s.invTTC, d?.level ?? 0, d?.gapPred ?? 0), privacy: .public)")
        }
        for d in decisions where d.level >= 2 {
            let s = stateByID[d.id]
            Self.log.log("\(String(format: "alert pts=%.2f id=%d cls=%@ level=%d grip=%@ z=%.1f invTTC=%.3f gapPred=%.2f", t, d.id, s?.cls.rawValue ?? "?", d.level, d.grip, s?.z ?? 0, s?.invTTC ?? 0, d.gapPred), privacy: .public)")
        }
        stat.count += 1; stat.ms.append(ms); stat.maxLag = max(stat.maxLag, lag)
        if t - stat.since >= 5 {
            let sorted = stat.ms.sorted()
            let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            let line = String(format: "summary pts=%.1f fps=%.1f dropped=%d inf_mean=%.1fms inf_p95=%.1fms max_lag=%.3f", t,
                              Double(stat.count) / (t - stat.since), dropped, sorted.reduce(0, +) / Double(sorted.count), p95, stat.maxLag)
            Self.log.log("\(line, privacy: .public)")
            stat = (0, [], 0, t)
        }

        frameTimes.append(t)
        frameTimes.removeAll { t - $0 > 1 }
        bench.append((t, ms))
        bench.removeAll { t - $0.t > 10 }

        let message = FrameMessage(
            t: t, fps: frameTimes.count, temp: input.thermal, speed: input.speed, heading: input.heading,
            demo: input.demo,
            tracks: states.filter { visible.contains($0.id) }.map { s in
                let d = byID[s.id]
                return TrackMessage(id: s.id, cls: s.cls, x: s.gap, z: s.z, invTTC: s.invTTC,
                                    gapPred: d?.gapPred ?? abs(s.gap), level: d?.level ?? 0,
                                    grip: d?.grip ?? "-", turnR: s.turnR)
            },
            merge: lastMerge.withLock { (m: inout MergeMessage?) -> MergeMessage? in
                // The front shows an answer for 3 s; stop sending it once it is spent.
                if let current = m, t - current.t > 3 { m = nil }
                return m
            })
        if t - lastSendT >= 1.0 / 15 {
            lastSendT = t
            peer.send(message)
        }

        let overlay = tracks.filter { visible.contains($0.id) }.map { tr in
            OverlayTrack(id: tr.id, cls: tr.cls,
                         rect: CGRect(x: tr.box.x / w, y: tr.box.y / h, width: tr.box.w / w, height: tr.box.h / h),
                         level: byID[tr.id]?.level ?? 0, z: stateByID[tr.id]?.z ?? 0)
        }
        let image = wantsPreviewImage
            ? ciContext.createCGImage(CIImage(cvPixelBuffer: frame.pixelBuffer), from: CGRect(x: 0, y: 0, width: w, height: h))
            : nil
        publish(RearSnapshot(message: message, overlay: overlay, inferenceMs: ms,
                             benchMs: bench.reduce(0) { $0 + $1.ms } / Double(max(bench.count, 1)),
                             peer: peer.state, previewImage: image,
                             focal: geo.f, focalFromLens: geoFromIntrinsics))
    }

    /// Bike yaw relative to a slow (2 s) reference heading. CoreMotion yaw is positive
    /// counter-clockwise; a right turn is a positive heading delta for GapEstimator.
    private func headingDelta(yaw: Double?, t: Double) -> Double {
        guard let yaw else { return 0 }
        guard let ref = yawRef else { yawRef = yaw; yawRefT = t; return 0 }
        let d = atan2(sin(yaw - ref), cos(yaw - ref))
        let alpha = min(1, max(0, (t - yawRefT) / 2))
        yawRef = ref + alpha * d
        yawRefT = t
        return -d
    }

    private func gapVelocity(id: Int, gap: Double, t: Double) -> Double {
        var v = 0.0
        if let prev = lastGap[id], t - prev.t > 0.01 {
            v = prev.v + 0.3 * ((gap - prev.gap) / (t - prev.t) - prev.v)
        }
        lastGap[id] = (gap, t, v)
        return v
    }

    /// Grip commands only on a change of (grip, level) per track; `X` once when no
    /// present track has alerted at level ≥ 2 any more (the engine downgrades to 1 after
    /// firing, so a literal per-frame check would clear the pattern mid-buzz).
    private func driveHaptics(decisions: [Decision], present: Set<Int>) {
        let hadAlert = sentLevel.values.contains { $0.level >= 2 }
        for d in decisions where d.level >= 2 {
            let key = (d.grip, d.level)
            // Buzz once per car: on its first alert, on a 2 -> 3 escalation, or if it moves to
            // the other grip. The engine reports the level every frame; repeats stay silent.
            if let prev = sentLevel[d.id], prev.grip == d.grip, prev.level >= d.level { continue }
            sentLevel[d.id] = key
            if let cmd = BLECommand.from(grip: d.grip, level: d.level) { sendHaptic(cmd) }
        }
        let holding = Set(decisions.map(\.id))
        sentLevel = sentLevel.filter { present.contains($0.key) || holding.contains($0.key) }
        let hasAlert = sentLevel.values.contains { $0.level >= 2 }
        if hadAlert && !hasAlert { sendHaptic(.clear) }
    }

    /// A handlebar button press. Called on the CoreBluetooth queue, never the worker's,
    /// so it reads the last published view rather than touching the pipeline.
    func handle(event: BLEEvent) {
        guard case .mergeRequest(let raw) = event, let side = MergeSide(rawValue: raw) else { return }
        let view = latest.withLock { $0 }
        let verdict = mergeCheck(side: side, tracks: view.states,
                                 age: Date().timeIntervalSince(view.wall))
        sendHaptic(verdict.clear ? .mergeClear(side: raw) : .mergeBlocked(side: raw))
        lastMerge.withLock {
            $0 = MergeMessage(side: raw, clear: verdict.clear, blockedBy: verdict.blockedBy, t: view.t)
        }
        Self.log.log("\(String(format: "merge %@ -> %@ (%@)", raw, verdict.clear ? "CLEAR" : "BLOCKED", verdict.reason), privacy: .public)")
    }

    private func syncLogger(on: Bool, frame: CapturedFrame) {
        if on, logger == nil {
            logger = try? RideLogger(width: CVPixelBufferGetWidth(frame.pixelBuffer),
                                     height: CVPixelBufferGetHeight(frame.pixelBuffer))
        } else if !on, let l = logger {
            l.finish(); logger = nil
        }
        logger?.append(frame.pixelBuffer, at: frame.timestamp)
    }
}
