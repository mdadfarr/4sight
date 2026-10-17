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
}

nonisolated struct RearSnapshot: @unchecked Sendable {
    var message: FrameMessage
    var overlay: [OverlayTrack]
    var inferenceMs: Double
    var benchMs: Double
    var peer: PeerLink.Rear.State
    var previewImage: CGImage?
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
    private let engine = ThreatEngine()
    private let danger = DangerAdapter()
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

        let hz = input.thermal == .serious || input.thermal == .critical ? 5.0 : Self.detectionHz
        guard t - lastDetectT >= 1 / hz - 0.001 else { return }
        let dt = lastDetectT.isFinite ? t - lastDetectT : 1 / hz
        lastDetectT = t

        let w = Double(CVPixelBufferGetWidth(frame.pixelBuffer))
        let h = Double(CVPixelBufferGetHeight(frame.pixelBuffer))
        if gapEstimator == nil || (frame.intrinsics != nil && !geoFromIntrinsics) {
            geoFromIntrinsics = frame.intrinsics != nil
            gapEstimator = GapEstimator(f: frame.intrinsics?.fx ?? 0.9 * w, u0: frame.intrinsics?.cx ?? w / 2,
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
            ttc.reset(id: tr.id); lastGap[tr.id] = nil   // size jump: history is from another vehicle or a cut
        }
        filter.forget(except: Set(tracks.map(\.id)))

        let yawCorrection = headingDelta(yaw: input.yaw, t: t)
        let states: [TrackState] = tracks.map { tr in
            let z = geo.range(box: tr.box, cls: tr.cls)
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
            (decisions, gripDecisions) = danger.update(tracks: tracks, t: t, imageW: w, imageH: h)
        } else {
            decisions = engine.update(tracks: states, bikeSpeed: input.speed, demoMode: input.demo, now: t)
            gripDecisions = decisions
        }
        let byID = Dictionary(decisions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        driveHaptics(decisions: gripDecisions, present: Set(tracks.map(\.id)))

        frameTimes.append(t)
        frameTimes.removeAll { t - $0 > 1 }
        bench.append((t, ms))
        bench.removeAll { t - $0.t > 10 }

        let message = FrameMessage(
            t: t, fps: frameTimes.count, temp: input.thermal, speed: input.speed, heading: input.heading,
            demo: input.demo,
            tracks: states.map { s in
                let d = byID[s.id]
                return TrackMessage(id: s.id, cls: s.cls, x: s.gap, z: s.z, invTTC: s.invTTC,
                                    gapPred: d?.gapPred ?? abs(s.gap), level: d?.level ?? 0,
                                    grip: d?.grip ?? "-", turnR: s.turnR)
            })
        if t - lastSendT >= 1.0 / 15 {
            lastSendT = t
            peer.send(message)
        }

        let overlay = tracks.map { tr in
            OverlayTrack(id: tr.id, cls: tr.cls,
                         rect: CGRect(x: tr.box.x / w, y: tr.box.y / h, width: tr.box.w / w, height: tr.box.h / h),
                         level: byID[tr.id]?.level ?? 0)
        }
        let image = wantsPreviewImage
            ? ciContext.createCGImage(CIImage(cvPixelBuffer: frame.pixelBuffer), from: CGRect(x: 0, y: 0, width: w, height: h))
            : nil
        publish(RearSnapshot(message: message, overlay: overlay, inferenceMs: ms,
                             benchMs: bench.reduce(0) { $0 + $1.ms } / Double(max(bench.count, 1)),
                             peer: peer.state, previewImage: image))
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
            if let prev = sentLevel[d.id], prev == key { continue }
            sentLevel[d.id] = key
            if let cmd = BLECommand.from(grip: d.grip, level: d.level) { sendHaptic(cmd) }
        }
        let holding = Set(decisions.map(\.id))
        sentLevel = sentLevel.filter { present.contains($0.key) || holding.contains($0.key) }
        let hasAlert = sentLevel.values.contains { $0.level >= 2 }
        if hadAlert && !hasAlert { sendHaptic(.clear) }
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
