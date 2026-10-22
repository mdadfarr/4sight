import Foundation
import Protocol

protocol TrackFeed {
    var frames: AsyncStream<FrameMessage> { get }
    func start()
    func stop()
}

/// Launch arguments: --synthetic, --freeze T, --mockroute, --demo (FrameMessage.demo,
/// which makes bicycles and people count as threats, matching ThreatEngine).
/// `-previewRide YES` (with `-role front`) laps a pretend live ride for the simulator.
struct LaunchArgs {
    let synthetic: Bool
    let freeze: Double?
    let mockRoute: Bool
    let demo: Bool
    let previewRide: Bool
    /// `-replayRear <file in Documents>`: with `-previewRide`, real rear-pipeline tracks.
    let replayRear: String?

    init(_ args: [String] = ProcessInfo.processInfo.arguments) {
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        synthetic = args.contains("--synthetic")
        freeze = value(after: "--freeze").flatMap(Double.init)
        mockRoute = args.contains("--mockroute")
        demo = args.contains("--demo")
        previewRide = args.contains("-previewRide")
        replayRear = value(after: "-replayRear")
    }
}
