import Foundation
import Perception
import Protocol
import os

/// `-replayRear <file>`: the real rear pipeline (detector, tracker, range, TTC,
/// ThreatEngine) run in this process on a clip in Documents, its frames fed straight to
/// the front. Lets a recorded rear camera drive the front view in the simulator.
///
/// Demo mode is on because the footage is mostly people; the engine is ThreatEngine.
final class RearReplayFeed: TrackFeed {
    let frames: AsyncStream<FrameMessage>
    private let continuation: AsyncStream<FrameMessage>.Continuation
    private let url: URL
    private var worker: RearWorker?

    /// shortcut: the clip carries no GPS, so the engine is told a steady 11 km/h (what
    /// the rear screen read on that ride); a ride logged with `Log ride` has its own.
    static let speed = 3.0

    init(file: String) {
        url = URL.documentsDirectory.appendingPathComponent(file)
        var cont: AsyncStream<FrameMessage>.Continuation!
        frames = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        continuation = cont
    }

    func start() {
        let cont = continuation
        do {
            let w = try RearWorker(source: FileSource(url: url), previewImage: false,
                                   sendHaptic: { _ in }, publish: { cont.yield($0.message) })
            w.inputs.withLock { $0.demo = true; $0.speed = Self.speed }
            try w.start()
            worker = w
        } catch {
            print("rear replay: \(error)")
        }
    }

    func stop() { worker?.stop(); worker = nil }
}
