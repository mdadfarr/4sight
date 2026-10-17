import Combine
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

    func stop() {
        consumer?.cancel()
        watchdog?.cancel()
        feed?.stop()
    }

    private func ingest(_ f: FrameMessage) {
        let t = now()
        lastFrameAt = t
        var next: [Int: Motion] = [:]
        for tr in f.tracks {
            let target = CGPoint(x: tr.x, y: tr.z)
            let from = motions[tr.id].map { position(of: $0, at: t) } ?? target
            next[tr.id] = Motion(from: from, to: target, arrival: t + Self.slide)
        }
        motions = next
        for tr in f.tracks { worstSeen[tr.id] = max(worstSeen[tr.id] ?? 0, tr.level) }
        frame = f
        link = .connected
        alerts.update(AlertBands.zones(SurroundView.visibleTracks(f)), now: t)
    }

    /// Visible tracks with their positions slid over the 0.1 s between frames, so
    /// traffic moves smoothly at 30 Hz on a 10 Hz feed.
    func tracks(at t: Double) -> [VehicleSprite.Track] {
        SurroundView.visibleTracks(frame).map { tr in
            guard let m = motions[tr.id] else { return tr }
            let p = position(of: m, at: t)
            return VehicleSprite.Track(id: tr.id, cls: tr.cls, x: p.x, z: p.y,
                                       level: tr.level, turnR: tr.turnR)
        }
        .sorted { $0.z < $1.z }
    }

    func position(of m: Motion, at t: Double) -> CGPoint {
        let f = min(max((t - m.arrival + Self.slide) / Self.slide, 0), 1)
        return CGPoint(x: m.from.x + (m.to.x - m.from.x) * f, y: m.from.y + (m.to.y - m.from.y) * f)
    }
}
