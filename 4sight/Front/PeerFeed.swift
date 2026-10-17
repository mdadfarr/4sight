import Foundation
import Links
import Protocol
import os

/// Live frames from the rear phone over the package's Bonjour/TCP link.
final class PeerFeed: TrackFeed {
    private let link = PeerLink.Front()
    var frames: AsyncStream<FrameMessage> { link.messages }

    /// What this phone advertises as, so the rear's `-peer` can name it. iOS reports
    /// every handset as "iPhone" without the device-name entitlement, so a rider with
    /// two bikes has to be able to tell them apart by hand.
    static let nameKey = "frontName"

    static var advertisedName: String {
        let saved = UserDefaults.standard.string(forKey: nameKey) ?? ""
        return saved.isEmpty ? PeerLink.deviceName : saved
    }

    func start() {
        // shortcut: a listener failure (port in use) is silent; the status dot stays amber. Surface it if it bites.
        do { try link.start(name: Self.advertisedName) } catch {
            Logger(subsystem: "com.zupersun.foursight", category: "peer").error("PeerFeed listener failed: \(error.localizedDescription)")
        }
    }

    func stop() { link.stop() }
}
