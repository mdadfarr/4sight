import Combine
import CoreLocation
import Foundation
import Protocol

@MainActor
final class FrontModel: ObservableObject {
    @Published private(set) var frame: FrameMessage?
    @Published private(set) var link: LinkState = .searching
    @Published var nav: NavState?

    /// Per-track motion: slides from `from` to `to`, arriving at `arrival` (0.1 s after the frame).
    struct Motion { var from: CGPoint; var to: CGPoint; var arrival: Double }
    private(set) var motions: [Int: Motion] = [:]

    /// How long each screen edge has held its level, so a band can flash on arrival.
    private(set) var alerts = AlertBands.History()

    static let slide = 0.1
    /// Time constant of the per-track position average, and how long a track takes to
    /// fade in or out. Display only.
    static let smoothing = 0.3
    static let fade = 0.2
    private var smoothed: [Int: CGPoint] = [:]
    private var born: [Int: Double] = [:]
    private var ghosts: [Int: (track: VehicleSprite.Track, lostAt: Double)] = [:]
    /// When set, every clock in the UI reads this value (deterministic screenshots).
    var freeze: Double?

    /// The worst level each track reached during this ride, so the summary counts a
    /// vehicle once however long it stayed alongside.
    private var worstSeen: [Int: Int] = [:]
    var closePasses: Int { worstSeen.values.filter { $0 == 2 }.count }
    var imminent: Int { worstSeen.values.filter { $0 >= 3 }.count }

    func beginRide() { worstSeen.removeAll() }

    /// True while the scripted ride is driving the screen. The HUD only falls back to
    /// the script's own street and distances then; on a live feed with no destination
    /// it says so instead of inventing a turn.
    private(set) var scripted = false

    /// Live mode only: the real route and which way the rider faces.
    var route = LiveRoute()

    func pose(_ loc: CLLocation, heading: Double?) {
        route.update(loc, heading: heading, at: now())
    }

    private var feed: TrackFeed?
    private var consumer: Task<Void, Never>?

    /// Seconds on the UI timebase for a TimelineView date.
    func now(_ date: Date = Date()) -> Double {
        freeze ?? date.timeIntervalSinceReferenceDate
    }

    /// Link counts as lost after this long without a frame.
    static let lostAfter = 1.5
    private var lastFrameAt: Double?
    private var watchdog: Task<Void, Never>?

    func start(feed: TrackFeed) {
        stop()
        self.feed = feed
        scripted = feed is SyntheticFeed
        link = .searching
        feed.start()
        consumer = Task { [weak self] in
            for await f in feed.frames {
                guard let self else { return }
                self.ingest(f)
            }
        }
        guard freeze == nil else { return }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let last = self.lastFrameAt else { continue }
                if self.now() - last > Self.lostAfter { self.link = .lost }
            }
        }
    }

    /// Re-advertise after the rider renames this phone: the Bonjour service name is
    /// fixed when the listener starts, so the link has to come back up to take it.
    func restartFeed() {
        guard let feed else { return }
        start(feed: feed)
    }

    func stop() {
        consumer?.cancel()
        watchdog?.cancel()
        feed?.stop()
    }

    private func ingest(_ f: FrameMessage) {
        let t = now()
        // A gap longer than half a second is a dropped link, not a slow frame.
        let dt = lastFrameAt.map { min(max(t - $0, 0), 0.5) } ?? 0
        lastFrameAt = t

        // Whatever was on screen and is not in this frame fades out from where it was.
        let before = tracks(at: t)
        let visibleNow = Set(SurroundView.visibleTracks(f).map(\.id))
        for tr in before where !visibleNow.contains(tr.id) && ghosts[tr.id] == nil {
            ghosts[tr.id] = (tr, t)
        }
        ghosts = ghosts.filter { !visibleNow.contains($0.key) && t - $0.value.lostAt < Self.fade }

        // The rear's per-frame range and offset are noisy; an exponential average per id
        // steadies what is drawn. Display only: levels and alerts read the raw frame.
        let a = 1 - exp(-dt / Self.smoothing)
        var next: [Int: Motion] = [:]
        var kept: [Int: CGPoint] = [:]
        for tr in f.tracks {
            let raw = CGPoint(x: centreX(tr.x, tr.cls.rawValue), y: tr.z)
            let target = smoothed[tr.id].map {
                CGPoint(x: $0.x + (raw.x - $0.x) * a, y: $0.y + (raw.y - $0.y) * a)
            } ?? raw
            kept[tr.id] = target
            if born[tr.id] == nil { born[tr.id] = t }
            let from = motions[tr.id].map { position(of: $0, at: t) } ?? target
            next[tr.id] = Motion(from: from, to: target, arrival: t + Self.slide)
        }
        smoothed = kept
        born = born.filter { kept[$0.key] != nil }
        motions = next
        for tr in f.tracks { worstSeen[tr.id] = max(worstSeen[tr.id] ?? 0, tr.level) }
        frame = f
        link = .connected
        alerts.update(AlertBands.zones(SurroundView.visibleTracks(f)), now: t)
    }

    /// Visible tracks with their positions slid over the 0.1 s between frames, so
    /// traffic moves smoothly at 30 Hz on a 10 Hz feed.
    /// The rear sends a vehicle's near side, the passing gap, not its centre. Drawn
    /// centred on that, every vehicle sat half its width too close to the bike. The
    /// scripted cues were written as centres, so the demo is left as it was.
    private func centreX(_ x: Double, _ cls: String) -> Double {
        guard !scripted, x != 0 else { return x }
        let half = World.size(cls).w / 2
        return x < 0 ? x - half : x + half
    }

    func tracks(at t: Double) -> [VehicleSprite.Track] {
        // A frozen clock never advances a fade, so screenshots draw everything solid.
        func fadeIn(_ id: Int) -> Double {
            guard freeze == nil, let b = born[id] else { return 1 }
            return min(max((t - b) / Self.fade, 0), 1)
        }
        let live = SurroundView.visibleTracks(frame).map { tr -> VehicleSprite.Track in
            let p = motions[tr.id].map { position(of: $0, at: t) } ?? CGPoint(x: centreX(tr.x, tr.cls), y: tr.z)
            return VehicleSprite.Track(id: tr.id, cls: tr.cls, x: p.x, z: p.y,
                                       level: tr.level, turnR: tr.turnR, opacity: fadeIn(tr.id))
        }
        let leaving = ghosts.values.compactMap { g -> VehicleSprite.Track? in
            let alpha = 1 - (t - g.lostAt) / Self.fade
            guard freeze == nil, alpha > 0 else { return nil }
            var tr = g.track
            tr.opacity = alpha * g.track.opacity
            return tr
        }
        return (live + leaving).sorted { $0.z < $1.z }
    }

    func position(of m: Motion, at t: Double) -> CGPoint {
        let f = min(max((t - m.arrival + Self.slide) / Self.slide, 0), 1)
        return CGPoint(x: m.from.x + (m.to.x - m.from.x) * f, y: m.from.y + (m.to.y - m.from.y) * f)
    }
}
