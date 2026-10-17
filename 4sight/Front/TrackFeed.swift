import Foundation
import Protocol

protocol TrackFeed {
    var frames: AsyncStream<FrameMessage> { get }
    func start()
    func stop()
}

/// Launch arguments: --synthetic, --scenario N, --freeze T, --mockroute.
struct LaunchArgs {
    let synthetic: Bool
    let scenario: Int
    let freeze: Double?
    let mockRoute: Bool

    init(_ args: [String] = ProcessInfo.processInfo.arguments) {
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        synthetic = args.contains("--synthetic")
        scenario = value(after: "--scenario").flatMap(Int.init) ?? 0
        freeze = value(after: "--freeze").flatMap(Double.init)
        mockRoute = args.contains("--mockroute")
    }
}
