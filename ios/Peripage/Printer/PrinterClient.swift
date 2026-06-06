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
        while sent < total {
            let end = min(sent + chunkSize, total)
            let chunk = payload[sent..<end]
            peripheral.writeValue(chunk, for: writeChar, type: .withoutResponse)
            sent = end
            state = .sending(jobId: jobId, progress: Double(sent) / Double(total))
            try await Task.sleep(for: PeripageProtocol.interChunkDelay)
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
        Task { @MainActor in
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
            peripheral.discoverServices(nil)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager,
                                           didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            let e = BLEError.writeFailed(description: error?.localizedDescription ?? "didFailToConnect")
            self.state = .error(e)
            self.pendingConnect?.resume(throwing: e); self.pendingConnect = nil
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager,
                                           didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
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
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral,
                                       didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            let targetUUID = CBUUID(string: PeripageProtocol.writeCharacteristicUUIDString)
            if let ch = service.characteristics?.first(where: { $0.uuid == targetUUID }) {
                self.writeChar = ch
                self.state = .connected(name: peripheral.name ?? "Peripage")
                self.pendingConnect?.resume(); self.pendingConnect = nil
                DebugLog.shared.info("Write characteristic ready")
            }
        }
    }
}
