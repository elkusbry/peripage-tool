import Foundation
import CoreBluetooth
import Observation

@MainActor
@Observable
public final class PrinterClient: NSObject, PrinterClientProtocol {
    public private(set) var state: PrinterState = .disconnected

    private let serviceQueue = DispatchQueue(label: "peripage.printer.ble")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?

    // Pending continuations
    private var pendingPowerOn: CheckedContinuation<Void, Error>?
    private var pendingScan: CheckedContinuation<CBPeripheral, Error>?
    private var pendingConnect: CheckedContinuation<Void, Error>?
    private var pendingReadyToSend: CheckedContinuation<Void, Never>?
    private var pendingWriteAck: CheckedContinuation<Void, Error>?

    private var scanTimer: Task<Void, Never>?

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: serviceQueue, options: nil)
    }

    public func ensureConnected() async throws {
        if case .connected = state { return }
        try await waitForPowerOn()
        let p = try await scanForPeripheral()
        try await connect(to: p)
    }

    public func send(_ payload: Data, jobId: UUID) async throws {
        guard let peripheral = peripheral, let writeChar = writeChar else {
            throw BLEError.characteristicNotFound
        }
        let total = payload.count
        var sent = 0
        let chunkSize = PeripageProtocol.chunkSize
        // PREFER .withResponse when supported: CoreBluetooth doesn't reliably
        // backpressure .withoutResponse on iOS — excess writes are silently
        // dropped once its internal queue is full. .withResponse waits for the
        // ATT-level write response, which is genuine end-to-end delivery.
        let writeType: CBCharacteristicWriteType =
            writeChar.properties.contains(.write) ? .withResponse : .withoutResponse
        DebugLog.shared.info("send: \(payload.count) bytes in chunks of \(chunkSize), type=\(writeType == .withoutResponse ? "WR" : "withResp")")
        while sent < total {
            let end = min(sent + chunkSize, total)
            let chunk = payload[sent..<end]

            if writeType == .withResponse {
                // Await per-write ACK so we never out-run the printer.
                try await withCheckedThrowingContinuation { (cc: CheckedContinuation<Void, Error>) in
                    self.pendingWriteAck = cc
                    peripheral.writeValue(chunk, for: writeChar, type: .withResponse)
                }
            } else {
                // .withoutResponse path: respect CoreBluetooth's flow control
                // by checking canSendWriteWithoutResponse and waiting for
                // peripheralIsReady(toSendWriteWithoutResponse:) when needed.
                if !peripheral.canSendWriteWithoutResponse {
                    await withCheckedContinuation { (cc: CheckedContinuation<Void, Never>) in
                        self.pendingReadyToSend = cc
                    }
                }
                peripheral.writeValue(chunk, for: writeChar, type: .withoutResponse)
            }

            sent = end
            state = .sending(jobId: jobId, progress: Double(sent) / Double(total))
            if (sent / chunkSize) % 16 == 0 || sent == total {
                DebugLog.shared.info("  sent \(sent)/\(total) (\(Int(Double(sent) * 100 / Double(total)))%)")
            }
        }
        // Settle: real printer needs ~3s to flush its buffer
        try await Task.sleep(for: .seconds(3))
        state = .connected(name: peripheral.name ?? "Peripage")
    }

    public func disconnect() async {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        writeChar = nil
        state = .disconnected
    }

    private static func describeProperties(_ p: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if p.contains(.read)                  { parts.append("read") }
        if p.contains(.write)                 { parts.append("write") }
        if p.contains(.writeWithoutResponse)  { parts.append("writeNR") }
        if p.contains(.notify)                { parts.append("notify") }
        if p.contains(.indicate)              { parts.append("indicate") }
        if p.contains(.broadcast)             { parts.append("broadcast") }
        return parts.joined(separator: ",")
    }
}

extension PrinterClient {
    private func waitForPowerOn() async throws {
        switch central.state {
        case .poweredOn:    return
        case .unauthorized: throw BLEError.bluetoothUnauthorized
        case .unsupported:  throw BLEError.bluetoothUnavailable
        case .poweredOff:   throw BLEError.bluetoothPoweredOff
        default: break
        }
        try await withCheckedThrowingContinuation { (cc: CheckedContinuation<Void, Error>) in
            self.pendingPowerOn = cc
        }
    }

    private func scanForPeripheral() async throws -> CBPeripheral {
        state = .scanning
        DebugLog.shared.info("Scanning for \(PeripageProtocol.nameNamePrefix)…")
        return try await withCheckedThrowingContinuation { cc in
            self.pendingScan = cc
            self.central.scanForPeripherals(withServices: nil, options: nil)
            self.scanTimer?.cancel()
            self.scanTimer = Task { [weak self] in
                try? await Task.sleep(for: PeripageProtocol.scanTimeout)
                await self?.scanTimedOut()
            }
        }
    }

    @MainActor
    private func scanTimedOut() {
        guard let cc = pendingScan else { return }
        central.stopScan()
        pendingScan = nil
        state = .error(.scanTimeout)
        cc.resume(throwing: BLEError.scanTimeout)
    }

    private func connect(to p: CBPeripheral) async throws {
        state = .connecting(name: p.name ?? "Peripage")
        peripheral = p
        p.delegate = self
        try await withCheckedThrowingContinuation { (cc: CheckedContinuation<Void, Error>) in
            self.pendingConnect = cc
            self.central.connect(p, options: nil)
        }
    }
}

extension PrinterClient: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if let cc = self.pendingPowerOn { self.pendingPowerOn = nil; cc.resume() }
            case .unauthorized:
                self.state = .error(.bluetoothUnauthorized)
                self.pendingPowerOn?.resume(throwing: BLEError.bluetoothUnauthorized); self.pendingPowerOn = nil
            case .poweredOff:
                self.state = .error(.bluetoothPoweredOff)
                self.pendingPowerOn?.resume(throwing: BLEError.bluetoothPoweredOff); self.pendingPowerOn = nil
            case .unsupported:
                self.state = .error(.bluetoothUnavailable)
                self.pendingPowerOn?.resume(throwing: BLEError.bluetoothUnavailable); self.pendingPowerOn = nil
            default: break
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager,
                                           didDiscover peripheral: CBPeripheral,
                                           advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        guard name.lowercased().contains(PeripageProtocol.nameNamePrefix.lowercased()) else { return }
        let rssi = RSSI.intValue
        Task { @MainActor in
            DebugLog.shared.info("Discovered \(name) rssi=\(rssi)")
            guard let cc = self.pendingScan else { return }
            self.pendingScan = nil
            self.scanTimer?.cancel(); self.scanTimer = nil
            self.central.stopScan()
            DebugLog.shared.info("Found \(name)")
            cc.resume(returning: peripheral)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            DebugLog.shared.info("Connected to \(peripheral.name ?? "?"), discovering services…")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager,
                                           didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let desc = error?.localizedDescription ?? "no error"
        Task { @MainActor in
            DebugLog.shared.error("didFailToConnect: \(desc)")
            let e = BLEError.writeFailed(description: error?.localizedDescription ?? "didFailToConnect")
            self.state = .error(e)
            self.pendingConnect?.resume(throwing: e); self.pendingConnect = nil
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager,
                                           didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let desc = error?.localizedDescription ?? "clean"
        Task { @MainActor in
            DebugLog.shared.warn("Disconnected: \(desc)")
            self.peripheral = nil
            self.writeChar = nil
            if case .sending = self.state {
                self.state = .error(.disconnectedDuringSend)
            } else {
                self.state = .disconnected
            }
        }
    }
}

extension PrinterClient: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            for service in peripheral.services ?? [] {
                DebugLog.shared.info("Discovered service: \(service.uuid.uuidString)")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral,
                                       didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            for ch in service.characteristics ?? [] {
                let props = Self.describeProperties(ch.properties)
                DebugLog.shared.info("  Char \(ch.uuid.uuidString) in svc \(service.uuid.uuidString) props=[\(props)]")
            }
            let targetUUID = CBUUID(string: PeripageProtocol.writeCharacteristicUUIDString)
            let candidates = (service.characteristics ?? []).filter { $0.uuid == targetUUID }
            let writable = candidates.first {
                $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write)
            }
            // Only pick once across the whole connection — don't let a later (config) service overwrite a good earlier pick.
            if let ch = writable, self.writeChar == nil {
                self.writeChar = ch
                self.state = .connected(name: peripheral.name ?? "Peripage")
                self.pendingConnect?.resume(); self.pendingConnect = nil
                let propStr = Self.describeProperties(ch.properties)
                DebugLog.shared.info("Selected write char \(ch.uuid.uuidString) in svc \(service.uuid.uuidString) props=[\(propStr)]")
            }
        }
    }

    /// Called when a `.withResponse` write completes (ACK or error from the peripheral).
    nonisolated public func peripheral(_ peripheral: CBPeripheral,
                                       didWriteValueFor characteristic: CBCharacteristic,
                                       error: Error?) {
        let desc = error?.localizedDescription
        Task { @MainActor in
            if let cc = self.pendingWriteAck {
                self.pendingWriteAck = nil
                if let desc {
                    DebugLog.shared.error("write error: \(desc)")
                    cc.resume(throwing: BLEError.writeFailed(description: desc))
                } else {
                    cc.resume()
                }
            }
        }
    }

    /// CoreBluetooth invokes this when its `.withoutResponse` send queue has
    /// drained enough to accept more writes — the canSendWriteWithoutResponse
    /// signal we need for proper backpressure.
    nonisolated public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Task { @MainActor in
            if let cc = self.pendingReadyToSend {
                self.pendingReadyToSend = nil
                cc.resume()
            }
        }
    }
}
