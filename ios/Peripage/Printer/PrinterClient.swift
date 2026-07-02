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
    private var pendingNotifyCount: Int = 0
    private var connectReadyFired: Bool = false

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
        connectReadyFired = false
        pendingNotifyCount = 0
        try await waitForPowerOn()
        let p = try await scanForPeripheral()
        try await connect(to: p)
    }

    /// Resume the connect continuation when all expected notify
    /// subscriptions have confirmed AND the write characteristic is
    /// known. A 2s safety timer fires the same resume if the device is
    /// slow to ack any subscription — better to print with one missing
    /// notify than to hang forever.
    private func tryFireConnectReady() {
        guard !connectReadyFired,
              writeChar != nil,
              pendingNotifyCount <= 0,
              let cc = pendingConnect
        else { return }
        connectReadyFired = true
        pendingConnect = nil
        DebugLog.shared.info("Connection settled — notifies subscribed, ready to send")
        cc.resume()
    }

    public func send(_ payload: Data, jobId: UUID) async throws {
        guard let peripheral = peripheral, let writeChar = writeChar else {
            throw BLEError.characteristicNotFound
        }
        let total = payload.count
        var sent = 0

        // Match the working Python tool: .withoutResponse with proper iOS
        // flow control. .withResponse adds 20–40ms per chunk while the
        // peripheral ACKs each write — the Peripage firmware's receive
        // buffer appears to time out under that pacing and silently
        // discards the job.
        let writeType: CBCharacteristicWriteType =
            writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse

        // Use the negotiated MTU rather than a hard-coded 96. Most BLE 4.2+
        // peripherals expose 100–250 bytes of payload; using more bytes per
        // write means fewer round-trips and less chance of buffer timeout.
        let maxLen = peripheral.maximumWriteValueLength(for: writeType)
        let chunkSize = min(PeripageProtocol.chunkSize, maxLen)
        DebugLog.shared.info("send: \(total) bytes, chunk=\(chunkSize) (mtu=\(maxLen)), type=\(writeType == .withoutResponse ? "WR" : "withResp")")

        // Deadline pacing + stall instrumentation. We schedule chunk n to go no
        // earlier than `scheduleAnchor + n × interChunkDelay` on a monotonic
        // clock, so overshoot (MainActor contention, timer coalescing) self-
        // corrects instead of accumulating. maxGap/stallCount let a bad print be
        // matched to a logged stall in the field — a gap with no image shift is
        // underrun (head starved); a shift would be receive-buffer overrun.
        let clock = ContinuousClock()
        let sendStart = clock.now
        var scheduleAnchor = sendStart
        var lastWriteAt = sendStart
        var chunkIndex = 0
        var maxGap: Duration = .zero
        var stallCount = 0

        while sent < total {
            let end = min(sent + chunkSize, total)
            let chunk = payload[sent..<end]
            chunkIndex += 1

            if writeType == .withResponse {
                try await withCheckedThrowingContinuation { (cc: CheckedContinuation<Void, Error>) in
                    self.pendingWriteAck = cc
                    peripheral.writeValue(chunk, for: writeChar, type: .withResponse)
                }
            } else {
                // Respect CoreBluetooth's outbound queue. Without this check
                // iOS silently drops writes once its internal queue is full.
                if !peripheral.canSendWriteWithoutResponse {
                    await withCheckedContinuation { (cc: CheckedContinuation<Void, Never>) in
                        self.pendingReadyToSend = cc
                    }
                }

                // Instrumentation: how long since the previous chunk actually
                // went out? A gap much larger than interChunkDelay is a stall
                // that can starve the print head.
                let writeAt = clock.now
                let gap = writeAt - lastWriteAt
                if gap > maxGap { maxGap = gap }
                if chunkIndex > 1 && gap > .milliseconds(40) {
                    stallCount += 1
                    let row = chunkIndex * chunkSize / PeripageProtocol.rowBytes
                    DebugLog.shared.warn("stall: chunk \(chunkIndex) gap \(String(format: "%.0f", gap.msValue))ms (row ~\(row))")
                }
                lastWriteAt = writeAt

                peripheral.writeValue(chunk, for: writeChar, type: .withoutResponse)

                // Deadline pacing. After a stall the loop sends back-to-back
                // (still gated by canSendWriteWithoutResponse) until back on
                // schedule — the burst that refills the starved printer buffer.
                // Cap catch-up: if we're more than maxPacingBacklog behind,
                // re-anchor so the burst stays bounded (~12 chunks).
                let deadline = scheduleAnchor + PeripageProtocol.interChunkDelay * chunkIndex
                let now = clock.now
                if now < deadline {
                    try await Task.sleep(until: deadline, clock: clock)
                } else if now - deadline > PeripageProtocol.maxPacingBacklog {
                    scheduleAnchor = now - PeripageProtocol.interChunkDelay * chunkIndex
                }
            }

            sent = end
            // Throttle the observable mutation to ~5Hz. Mutating on every chunk
            // interleaves SwiftUI diffing with the send loop on this actor and
            // was a contributor to the pacing jitter.
            if chunkIndex % 16 == 0 || sent == total {
                state = .sending(jobId: jobId, progress: Double(sent) / Double(total))
                DebugLog.shared.info("  sent \(sent)/\(total) (\(Int(Double(sent) * 100 / Double(total)))%)")
            }
        }

        let elapsed = clock.now - sendStart
        let secs = elapsed.msValue / 1000
        let kbps = secs > 0 ? Double(total) / 1024 / secs : 0
        DebugLog.shared.info("send complete: \(total)B in \(String(format: "%.1f", secs))s (\(String(format: "%.1f", kbps)) KB/s), stalls>40ms: \(stallCount), max gap: \(String(format: "%.0f", maxGap.msValue))ms")

        // Settle: real printer needs ~3s to flush its buffer
        DebugLog.shared.info("send done; waiting 3s for printer to flush")
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
                // Subscribe to every notify characteristic. Some firmwares
                // (this Peripage variant included) won't honour print
                // commands until they observe a subscriber on their status
                // channel — we wait for these to confirm before declaring
                // the connection ready to send.
                if ch.properties.contains(.notify) {
                    self.pendingNotifyCount += 1
                    peripheral.setNotifyValue(true, for: ch)
                    DebugLog.shared.info("  Subscribing to \(ch.uuid.uuidString)")
                }
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
                let propStr = Self.describeProperties(ch.properties)
                let mtuWR = peripheral.maximumWriteValueLength(for: .withoutResponse)
                let mtuW = peripheral.maximumWriteValueLength(for: .withResponse)
                DebugLog.shared.info("Selected write char \(ch.uuid.uuidString) in svc \(service.uuid.uuidString) props=[\(propStr)]")
                DebugLog.shared.info("Negotiated MTU: writeNR=\(mtuWR) write=\(mtuW)")
                // Safety net: if any notify subscription is slow to ack,
                // resume the connect after 2s anyway.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard let self else { return }
                    if !self.connectReadyFired {
                        DebugLog.shared.warn("Notify subscribe timeout — proceeding anyway")
                        self.pendingNotifyCount = 0
                        self.tryFireConnectReady()
                    }
                }
                self.tryFireConnectReady()
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral,
                                       didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                       error: Error?) {
        let uuid = characteristic.uuid.uuidString
        let enabled = characteristic.isNotifying
        let desc = error?.localizedDescription
        Task { @MainActor in
            if let desc {
                DebugLog.shared.warn("notify \(uuid) error: \(desc)")
            } else {
                DebugLog.shared.info("notify \(uuid) → \(enabled ? "ON" : "OFF")")
            }
            if enabled {
                self.pendingNotifyCount -= 1
                self.tryFireConnectReady()
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral,
                                       didUpdateValueFor characteristic: CBCharacteristic,
                                       error: Error?) {
        let uuid = characteristic.uuid.uuidString
        let bytes = characteristic.value.map { $0.map { String(format: "%02x", $0) }.joined(separator: " ") } ?? "(nil)"
        Task { @MainActor in
            DebugLog.shared.info("notify \(uuid) → \(bytes)")
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

private extension Duration {
    /// Whole + fractional milliseconds, for logging only.
    var msValue: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
