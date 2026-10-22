import Foundation
import Protocol

protocol TrackFeed {
    var frames: AsyncStream<FrameMessage> { get }
    func start()
    func stop()
}
