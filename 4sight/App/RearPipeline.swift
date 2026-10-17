import AVFoundation
import Combine
import CoreLocation
import CoreMotion
import Foundation
import Links
import Perception
import Protocol
import SwiftUI
import os

/// Main-actor face of the rear role: owns the sensors and the worker, publishes what the UI shows.
@MainActor final class RearPipeline: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var fps = 0
    @Published private(set) var inferenceMs = 0.0
    @Published private(set) var benchMs = 0.0
    @Published private(set) var thermal: ThermalLabel = .nominal
    @Published private(set) var speed = 0.0
    @Published private(set) var heading = -1.0
    @Published private(set) var peerState: PeerLink.Rear.State = .browsing
    @Published private(set) var overlay: [OverlayTrack] = []
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var error: String?
    @Published private(set) var eventCount = EventLogger.shared.count
    @Published var demoMode = false { didSet { syncInputs() } }
    @Published var logging = false { didSet { syncInputs() } }
    @Published var engine: Engine = .threat { didSet { syncInputs() } }
    /// Frame-fraction rectangles hiding the bike's own parts; `-exclude x1,y1,x2,y2[;...]` at launch.
    @Published var exclusionZones: [DetectionFilter.Zone] = [] { didSet { syncInputs() } }
    @Published private(set) var replayURL: URL?

    let haptics = HapticsLink()
    var captureSession: AVCaptureSession? { (worker?.source as? CameraSource)?.session }
    var trackCount: Int { overlay.count }

    private var worker: RearWorker?
    private let location = CLLocationManager()
    private let motion = CMMotionManager()
    private var thermalObserver: NSObjectProtocol?
    /// GPS log of the clip being replayed; the Simulator's own location is useless for this.
    private var rideTrack: RideTrack?
    private var firstFrameT: Double?

    override init() {
        super.init()
        if let path = UserDefaults.standard.string(forKey: "replay") { replayURL = URL(fileURLWithPath: path) }
        // -peer <name>: pair with that front only. Set here rather than passed down,
        // because the browser is built inside RearWorker. Must precede start().
        PeerLink.preferredFront = UserDefaults.standard.string(forKey: "peer")
        if let text = UserDefaults.standard.string(forKey: "exclude") {
            exclusionZones = text.split(separator: ";").compactMap { DetectionFilter.Zone(String($0)) }
        }
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    }

    func start() {
        stop()
        error = nil
        let source: CaptureSource
        if let url = replayURL {
            let file = FileSource(url: url)
            rideTrack = file.ride.track
            source = file
        } else {
            rideTrack = nil
            source = CameraSource()
        }
        firstFrameT = nil
        speed = 0
        heading = -1
        do {
            let w = try RearWorker(source: source, previewImage: replayURL != nil,
                                   sendHaptic: { [haptics] cmd in DispatchQueue.main.async { haptics.send(cmd) } },
                                   publish: { [weak self] snap in Task { @MainActor in self?.apply(snap) } })
            worker = w
            // Handlebar button presses arrive on the Bluetooth queue and are answered there.
            haptics.onEvent = { [weak w] event in w?.handle(event: event) }
            thermal = Self.label(ProcessInfo.processInfo.thermalState)
            syncInputs()
            try w.start()
        } catch {
            self.error = "\(error)"
            return
        }
        location.requestWhenInUseAuthorization()
        location.startUpdatingLocation()
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 30
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] m, _ in
                guard let yaw = m?.attitude.yaw else { return }
                self?.worker?.inputs.withLock { $0.yaw = yaw }
            }
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.thermal = Self.label(ProcessInfo.processInfo.thermalState)
                self?.syncInputs()
            }
        }
    }

    func stop() {
        worker?.stop()
        worker = nil
        location.stopUpdatingLocation()
        motion.stopDeviceMotionUpdates()
        if let o = thermalObserver { NotificationCenter.default.removeObserver(o) }
        thermalObserver = nil
    }

    /// Switch the source; nil goes back to the live camera. Restarts if running.
    func setReplay(_ url: URL?) {
        replayURL?.stopAccessingSecurityScopedResource()
        _ = url?.startAccessingSecurityScopedResource()
        replayURL = url
        if worker != nil { start() }
    }

    private func apply(_ s: RearSnapshot) {
        replayGPS(frameT: s.message.t)
        fps = s.message.fps
        inferenceMs = s.inferenceMs
        benchMs = s.benchMs
        peerState = s.peer
        overlay = s.overlay
        eventCount = EventLogger.shared.count
        if let img = s.previewImage { previewImage = img }
    }

    /// While replaying, the clip's own GPS log stands in for CoreLocation. Frame times and
    /// fix times are each measured from their file's first entry, so a ride extracted by
    /// `tools/mcap_to_ride.py` (t from the first frame) and one logged by `RideLogger`
    /// (t from systemUptime) both line up. The speed reaches the engine one frame late.
    private func replayGPS(frameT: Double) {
        guard let track = rideTrack else { return }
        let first = firstFrameT ?? frameT
        firstFrameT = first
        guard let fix = track.fix(at: frameT - first), fix.speed != speed || fix.heading != heading else { return }
        speed = fix.speed
        heading = fix.heading
        syncInputs()
    }

    /// Copies the main-actor sensor/toggle values into the worker (yaw arrives separately).
    private func syncInputs() {
        let (demo, log, temp, spd, hdg, zones, eng) = (demoMode, logging, thermal, speed, heading, exclusionZones, engine)
        worker?.inputs.withLock {
            $0.demo = demo; $0.logging = log; $0.thermal = temp; $0.speed = spd; $0.heading = hdg
            $0.exclusionZones = zones; $0.engine = eng
        }
    }

    nonisolated static func label(_ s: ProcessInfo.ThermalState) -> ThermalLabel {
        switch s {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        default: return .critical
        }
    }

    // MARK: CLLocationManagerDelegate (main queue)

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard replayURL == nil else { return }   // replayGPS owns speed/heading during a replay
        guard let loc = locations.last else { return }
        speed = max(loc.speed, 0)
        heading = loc.course >= 0 ? loc.course : -1
        EventLogger.shared.setFix(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
        syncInputs()
        // t matches the camera clock (host uptime) so the jsonl lines up with the .mov.
        let line = String(format: "{\"t\":%.3f,\"lat\":%.6f,\"lon\":%.6f,\"speed\":%.2f,\"heading\":%.1f}",
                          ProcessInfo.processInfo.systemUptime, loc.coordinate.latitude,
                          loc.coordinate.longitude, speed, heading)
        worker?.logLocation(line)
    }
}
