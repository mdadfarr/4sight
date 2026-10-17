import Combine
import Foundation
import Protocol


@MainActor
final class FrontModel: ObservableObject {
    @Published private(set) var frame: FrameMessage?
    @Published private(set) var link: LinkState = .searching

    private var feed: TrackFeed?
    private var consumer: Task<Void, Never>?

    func start(feed: TrackFeed) {
        stop()
        self.feed = feed
        feed.start()
        consumer = Task { [weak self] in
            for await f in feed.frames {
                guard let self else { return }
                self.frame = f
                self.link = .connected
            }
        }
    }

    func stop() {
        consumer?.cancel()
        feed?.stop()
    }
}
