#if os(iOS)
import Foundation
import Network
import Protocol
import os

public enum PeerLink {
    public static let serviceType = "_foursight._tcp"
    static let log = Logger(subsystem: "com.zupersun.foursight", category: "peer")

    static var parameters: NWParameters {
        let p = NWParameters.tcp
        p.includePeerToPeer = true
        return p
    }

    /// Rear phone: browses for the front phone and streams FrameMessages to it.
    public final class Rear: @unchecked Sendable {
        public enum State: Equatable { case browsing, connecting, connected }
        public private(set) var state: State = .browsing
        private let queue = DispatchQueue(label: "foursight.peer.rear")
        private var browser: NWBrowser?
        private var connection: NWConnection?

        public init() {}

        public func start() { queue.async { self.browse() } }

        public func stop() {
            queue.async {
                self.connection?.cancel(); self.connection = nil
                self.browser?.cancel(); self.browser = nil
            }
        }

        public func send(_ msg: FrameMessage) {
            guard let data = try? msg.encodeLine() else { return }
            queue.async {
                guard let c = self.connection, self.state == .connected else { return }
                c.send(content: data, completion: .contentProcessed { err in
                    if let err { PeerLink.log.error("rear send failed: \(err.localizedDescription)") }
                    else { PeerLink.log.debug("rear sent frame t=\(msg.t) tracks=\(msg.tracks.count)") }
                })
            }
        }

        private func browse() {
            state = .browsing
            let b = NWBrowser(for: .bonjour(type: PeerLink.serviceType, domain: nil), using: PeerLink.parameters)
            browser = b
            b.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self else { return }
                PeerLink.log.info("rear browser results=\(results.count)")
                guard self.connection == nil, let first = results.first else { return }
                self.connect(to: first.endpoint)
            }
            b.stateUpdateHandler = { [weak self] st in
                PeerLink.log.info("rear browser state=\(String(describing: st))")
                if case .failed = st { self?.queue.asyncAfter(deadline: .now() + 1) { self?.browse() } }
            }
            b.start(queue: queue)
        }

        private func connect(to endpoint: NWEndpoint) {
            state = .connecting
            let c = NWConnection(to: endpoint, using: PeerLink.parameters)
            connection = c
            c.stateUpdateHandler = { [weak self] st in
                guard let self else { return }
                PeerLink.log.info("rear connection to \(String(describing: endpoint)) state=\(String(describing: st))")
                switch st {
                case .ready: self.state = .connected
                case .failed, .cancelled:
                    c.cancel()
                    self.connection = nil
                    self.browser?.cancel()
                    self.queue.asyncAfter(deadline: .now() + 1) { self.browse() }
                default: break
                }
            }
            c.start(queue: queue)
        }
    }

    /// Front phone: advertises the Bonjour service and yields parsed FrameMessages.
    public final class Front: @unchecked Sendable {
        public let messages: AsyncStream<FrameMessage>
        private var continuation: AsyncStream<FrameMessage>.Continuation?
        private let queue = DispatchQueue(label: "foursight.peer.front")
        private var listener: NWListener?
        private var connection: NWConnection?
        private var buffer = Data()

        public init() {
            var cont: AsyncStream<FrameMessage>.Continuation?
            messages = AsyncStream(bufferingPolicy: .bufferingNewest(4)) { cont = $0 }
            continuation = cont
        }

        public func start() throws {
            let l = try NWListener(using: PeerLink.parameters)
            l.service = NWListener.Service(name: "4sight", type: PeerLink.serviceType)
            l.newConnectionHandler = { [weak self] c in
                guard let self else { return }
                PeerLink.log.info("front accepted connection from \(String(describing: c.endpoint))")
                // Only one rear phone; a newcomer replaces a stale connection.
                self.connection?.cancel()
                self.connection = c
                self.buffer.removeAll()
                c.start(queue: self.queue)
                self.receive(on: c)
            }
            l.stateUpdateHandler = { st in PeerLink.log.info("front listener state=\(String(describing: st))") }
            listener = l
            l.start(queue: queue)
        }

        public func stop() {
            queue.async { self.connection?.cancel(); self.listener?.cancel() }
        }

        private func receive(on c: NWConnection) {
            c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
                guard let self else { return }
                if let data { self.consume(data) }
                if done || error != nil { return }
                self.receive(on: c)
            }
        }

        private func consume(_ data: Data) {
            buffer.append(data)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                if let msg = try? FrameMessage.decode(line: Data(line)) {
                    PeerLink.log.debug("front decoded frame t=\(msg.t) tracks=\(msg.tracks.count)")
                    continuation?.yield(msg)
                } else { PeerLink.log.error("front undecodable line (\(line.count) bytes)") }
            }
        }
    }
}
#endif
