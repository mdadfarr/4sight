#if os(iOS)
import Combine
import Foundation
import Network
import os
import Protocol

/// UDP link to the ESP32, which hosts its own Wi-Fi network (docs/CONTRACTS.md, "Rear ↔ ESP32").
/// The rear phone joins `4sight-bike` once in Settings; this sends commands to 192.168.4.1:4210,
/// heartbeats every 200 ms, and counts the link as up while the ESP32's `A` replies keep coming.
/// Same surface as the BLE HapticsLink, so the pipeline swaps one line.
public final class WiFiHapticsLink: ObservableObject, @unchecked Sendable {
    public enum State: Equatable { case searching, connected }

    @Published public private(set) var state: State = .searching

    /// Called on the link's queue when the ESP32 reports a handlebar button press.
    public var onEvent: ((BLEEvent) -> Void)?

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "foursight.esp32")
    private var connection: NWConnection?
    private var heartbeat: DispatchSourceTimer?
    private var lastAck = Date.distantPast
    private static let log = Logger(subsystem: "com.zupersun.foursight", category: "esp32")

    public init(host: String = "192.168.4.1", port: UInt16 = 4210) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port) ?? 4210
        queue.async { self.open() }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.2, repeating: 0.2)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        heartbeat = t
    }

    deinit { heartbeat?.cancel(); connection?.cancel() }

    public func send(_ cmd: BLECommand) {
        queue.async { self.connection?.send(content: cmd.data, completion: .idempotent) }
    }

    // MARK: - On `queue`

    private func open() {
        let params = NWParameters.udp
        // Only over Wi-Fi: 192.168.4.1 means nothing on cellular, and this keeps the flow
        // waiting until the phone is on the ESP32's network instead of failing.
        params.requiredInterfaceType = .wifi
        let c = NWConnection(host: host, port: port, using: params)
        c.stateUpdateHandler = { [weak self] st in
            Self.log.info("esp32 udp \(String(describing: st), privacy: .public)")
            // A UDP flow only fails on a local error (e.g. the interface went away); start over.
            if case .failed = st { self?.queue.asyncAfter(deadline: .now() + 1) { self?.reopen() } }
        }
        connection = c
        c.start(queue: queue)
        receive(on: c)
    }

    private func reopen() {
        connection?.cancel()
        open()
    }

    private func receive(on c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let text = String(data: data, encoding: .utf8) {
                if text == "A" {
                    self.lastAck = Date()
                } else if let event = BLEEvent.parse(text) {
                    self.onEvent?(event)
                }
            }
            // Keep listening on this flow until it is replaced. ICMP "port unreachable" from a
            // network without the ESP32 surfaces as an error here and is not fatal for UDP, but
            // retrying it instantly would spin, so back off half a second after an error.
            guard c === self.connection, c.state != .cancelled else { return }
            if error == nil {
                self.receive(on: c)
            } else {
                self.queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    if c === self?.connection { self?.receive(on: c) }
                }
            }
        }
    }

    private func tick() {
        connection?.send(content: BLECommand.heartbeat.data, completion: .idempotent)
        let up = Date().timeIntervalSince(lastAck) < 1.0
        let next: State = up ? .connected : .searching
        DispatchQueue.main.async { [weak self] in
            if self?.state != next { self?.state = next }
        }
    }
}
#endif
