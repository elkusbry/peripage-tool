import Foundation

public enum PrinterState: Equatable, Sendable {
    case disconnected
    case scanning
    case connecting(name: String)
    case connected(name: String)
    case sending(jobId: UUID, progress: Double)
    case error(BLEError)
}

public enum BLEError: Error, Equatable, Sendable {
    case bluetoothUnavailable
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case scanTimeout
    case noPeripheralFound
    case serviceNotFound
    case characteristicNotFound
    case writeFailed(description: String)
    case disconnectedDuringSend
    case cancelled
}
