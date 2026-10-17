import Foundation
import Links
import Protocol
import os

/// Live frames from the rear phone over the package's Bonjour/TCP link.
final class PeerFeed: TrackFeed {
    private let link = PeerLink.Front()
    var frames: AsyncStream<FrameMessage> { link.messages }

    func start() {
        // shortcut: a listener failure (port in use) is silent; the status dot stays amber. Surface it if it bites.
        do { try link.start() } catch {
            Logger(subsystem: "com.zupersun.foursight", category: "peer").error("PeerFeed listener failed: \(error.localizedDescription)")
        }
    }

    func stop() { link.stop() }
}
