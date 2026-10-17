import Foundation
import Protocol

protocol TrackFeed {
    var frames: AsyncStream<FrameMessage> { get }
    func start()
    func stop()
}

/// Launch arguments: --synthetic, --freeze T, --mockroute, --demo (FrameMessage.demo,
/// which makes bicycles and people count as threats, matching ThreatEngine) and
/// --demoevents (scripted near misses on the risk map, for a phone that has not ridden).
struct LaunchArgs {
    let synthetic: Bool
    let freeze: Double?
    let mockRoute: Bool
    let demo: Bool
    let demoEvents: Bool

    init(_ args: [String] = ProcessInfo.processInfo.arguments) {
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        synthetic = args.contains("--synthetic")
        freeze = value(after: "--freeze").flatMap(Double.init)
        mockRoute = args.contains("--mockroute")
        demo = args.contains("--demo")
        demoEvents = args.contains("--demoevents")
    }
}
