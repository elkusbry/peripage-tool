import Foundation
import CoreBluetooth
import Observation

/// Acts as a *fake* Peripage A6 over BLE. The official Peripage iOS app
/// (or any other Peripage client) will discover this advertisement, see
/// the expected FF00 service + FF01/FF02/FF03 characteristics, and write
/// its print bytes to us — which we accumulate so they can be exported.
///
/// Usage:
///   1. Power the REAL printer off (or forget it in Settings → Bluetooth).
///   2. Tap Start. We start advertising.
///   3. Open the official Peripage app and "print" anything. It should
///      connect to us instead of the real printer.
///   4. Watch the byte counter climb. Tap Stop when no more bytes arrive.
///   5. Export via the Share button to get the .bin file.
@MainActor
@Observable
public final class CaptureClient: NSObject {
    public enum CapState: Equatable {
        case idle
        case bluetoothNotReady(String)
        case advertising
        case connected(centralName: String)
        case stopped
    }

    public private(set) var state: CapState = .idle
    public private(set) var captured: Data = Data()
    public var bytesReceived: Int { captured.count }
    public private(set) var statusLine: String = "Idle"

    private let serviceQueue = DispatchQueue(label: "peripage.capture.ble")
    private var manager: CBPeripheralManager!

    // Mirror the Peripage's real service shape so the official app
    // recognizes us as a valid target.
    private static let ff00 = CBUUID(string: "FF00")
    private static let ff01 = CBUUID(string: "FF01")  // notify in real device
    private static let ff02 = CBUUID(string: "FF02")  // write + writeNR
    private static let ff03 = CBUUID(string: "FF03")  // notify

    private var ff01Char: CBMutableCharacteristic?
    private var ff03Char: CBMutableCharacteristic?

    public override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: serviceQueue, options: nil)
    }

    public func start() {
        guard manager.state == .poweredOn else {
            statusLine = "Bluetooth not ready: \(describe(manager.state))"
            return
        }
        configureServices()
        startAdvertising()
    }

    public func stop() {
        if manager.isAdvertising { manager.stopAdvertising() }
        manager.removeAllServices()
        state = .stopped
        statusLine = "Stopped — \(captured.count) bytes captured"
        DebugLog.shared.info("Capture stopped — \(captured.count) bytes")
    }

    public func clear() {
        captured = Data()
        statusLine = "Cleared"
    }

    /// Write the capture to a temp file so it can be shared.
    public func exportURL() -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let ts = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("peripage-capture-\(ts).bin")
        do {
            try captured.write(to: url)
            DebugLog.shared.info("Capture exported to \(url.lastPathComponent)")
            return url
        } catch {
            statusLine = "Export failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Setup

    private func configureServices() {
        // FF02 must be writeable. Real device advertises [write, writeNR]
        // — match that so the official app picks the right write type.
        let ff02Char = CBMutableCharacteristic(
            type: Self.ff02,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        let ff01Char = CBMutableCharacteristic(
            type: Self.ff01,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )
        let ff03Char = CBMutableCharacteristic(
            type: Self.ff03,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )
        self.ff01Char = ff01Char
        self.ff03Char = ff03Char

        let svc = CBMutableService(type: Self.ff00, primary: true)
        svc.characteristics = [ff01Char, ff02Char, ff03Char]
        manager.add(svc)
    }

    private func startAdvertising() {
        let adData: [String: Any] = [
            // Use a name the official app's prefix scan will match.
            CBAdvertisementDataLocalNameKey: "PeriPage+CAPTR",
            CBAdvertisementDataServiceUUIDsKey: [Self.ff00],
        ]
        manager.startAdvertising(adData)
        state = .advertising
        statusLine = "Advertising as PeriPage+CAPTR — open the official app and print"
        DebugLog.shared.info("Capture started — advertising")
    }

    private func describe(_ s: CBManagerState) -> String {
        switch s {
        case .poweredOff:   return "powered off"
        case .poweredOn:    return "powered on"
        case .resetting:    return "resetting"
        case .unauthorized: return "unauthorized"
        case .unknown:      return "unknown"
        case .unsupported:  return "unsupported"
        @unknown default:   return "?"
        }
    }
}

extension CaptureClient: CBPeripheralManagerDelegate {
    nonisolated public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let s = peripheral.state
        Task { @MainActor in
            switch s {
            case .poweredOn:
                if case .idle = self.state {
                    self.statusLine = "Ready — tap Start"
                }
            case .poweredOff:
                self.state = .bluetoothNotReady("powered off")
                self.statusLine = "Bluetooth is off"
            case .unauthorized:
                self.state = .bluetoothNotReady("unauthorized")
                self.statusLine = "Bluetooth permission needed"
            default:
                self.statusLine = "BT state: \(self.describe(s))"
            }
        }
    }

    nonisolated public func peripheralManager(_ peripheral: CBPeripheralManager,
                                              didReceiveWrite requests: [CBATTRequest]) {
        // Copy bytes out before respond() — CBATTRequest is short-lived.
        let chunks: [Data] = requests.compactMap { $0.value }
        let centralIds = requests.map { $0.central.identifier.uuidString }
        for r in requests {
            peripheral.respond(to: r, withResult: .success)
        }
        Task { @MainActor in
            for d in chunks { self.captured.append(d) }
            if case .advertising = self.state, let first = centralIds.first {
                self.state = .connected(centralName: first.prefix(8).description)
            }
            let total = self.captured.count
            self.statusLine = "Receiving… \(total) bytes (last chunk: \(chunks.last?.count ?? 0))"
            DebugLog.shared.info("Capture +\(chunks.reduce(0){ $0 + $1.count }) (total \(total))")
        }
    }

    nonisolated public func peripheralManager(_ peripheral: CBPeripheralManager,
                                              central: CBCentral,
                                              didSubscribeTo characteristic: CBCharacteristic) {
        let uuid = characteristic.uuid.uuidString
        let cid = central.identifier.uuidString
        Task { @MainActor in
            DebugLog.shared.info("Central \(cid.prefix(8)) subscribed to \(uuid)")
        }
    }
}
