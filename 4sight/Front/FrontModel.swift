import Combine
import Foundation
import Protocol

@MainActor
final class FrontModel: ObservableObject {
    @Published private(set) var frame: FrameMessage?
    @Published private(set) var link: LinkState = .searching

    /// Per-track motion: slides from `from` to `to`, arriving at `arrival` (0.1 s after the frame).
    struct Motion { var from: CGPoint; var to: CGPoint; var arrival: Double }
    private(set) var motions: [Int: Motion] = [:]

    static let slide = 0.1
    /// When set, every clock in the UI reads this value (deterministic screenshots).
    var freeze: Double?

    private var feed: TrackFeed?
    private var consumer: Task<Void, Never>?

    /// Seconds on the UI timebase for a TimelineView date.
    func now(_ date: Date = Date()) -> Double {
        freeze ?? date.timeIntervalSinceReferenceDate
    }

    func start(feed: TrackFeed) {
        stop()
        self.feed = feed
        feed.start()
        consumer = Task { [weak self] in
            for await f in feed.frames {
                guard let self else { return }
                self.ingest(f)
            }
        }
    }

    func stop() {
        consumer?.cancel()
        feed?.stop()
    }

    private func ingest(_ f: FrameMessage) {
        let t = now()
        var next: [Int: Motion] = [:]
        for tr in f.tracks {
            let target = CGPoint(x: tr.x, y: tr.z)
            let from = motions[tr.id].map { position(of: $0, at: t) } ?? target
            next[tr.id] = Motion(from: from, to: target, arrival: t + Self.slide)
        }
        motions = next
        frame = f
        link = .connected
    }

    func position(of m: Motion, at t: Double) -> CGPoint {
        let f = min(max((t - m.arrival + Self.slide) / Self.slide, 0), 1)
        return CGPoint(x: m.from.x + (m.to.x - m.from.x) * f, y: m.from.y + (m.to.y - m.from.y) * f)
    }
}
