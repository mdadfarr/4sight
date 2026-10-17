#if os(iOS)
import CoreBluetooth
import Combine
import Protocol

/// CoreBluetooth central for the ESP32 grip. Reconnects forever; heartbeats every 200 ms.
public final class HapticsLink: NSObject, ObservableObject, CBCentralManagerDelegate,
                                CBPeripheralDelegate, @unchecked Sendable {
    public enum State: Equatable { case off, scanning, connecting, connected }

    @Published public private(set) var state: State = .off

    private let serviceUUID = CBUUID(string: BLEIDs.service)
    private let commandUUID = CBUUID(string: BLEIDs.command)
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var heartbeat: Timer?

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    public func send(_ cmd: BLECommand) {
        guard let p = peripheral, let c = characteristic, state == .connected else { return }
        p.writeValue(cmd.data, for: c, type: .withoutResponse)
    }

    private func scan() {
        guard central.state == .poweredOn else { return }
        state = .scanning
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { scan() } else { state = .off }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                               error: Error?) { scan() }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        heartbeat?.invalidate(); heartbeat = nil
        characteristic = nil
        scan()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        peripheral.discoverCharacteristics([commandUUID], for: s)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        guard let c = service.characteristics?.first(where: { $0.uuid == commandUUID }) else { return }
        characteristic = c
        state = .connected
        heartbeat = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.send(.heartbeat)
        }
    }
}
#endif
