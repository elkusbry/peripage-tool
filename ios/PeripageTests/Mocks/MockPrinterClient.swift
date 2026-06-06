import Foundation
@testable import Peripage

/// Configurable in-memory printer. Records every call, and can be told to
/// fail on `ensureConnected` or `send` for retry tests.
final class MockPrinterClient: PrinterClientProtocol, @unchecked Sendable {
    enum Failure: Equatable {
        case connectThrows(BLEError)
        case sendThrows(BLEError)
    }

    private let lock = NSLock()
    private var _state: PrinterState = .disconnected
    private(set) var sends: [(jobId: UUID, payloadLen: Int)] = []
    private(set) var connectCalls = 0
    private(set) var disconnectCalls = 0
    var nextFailures: [Failure] = []

    var state: PrinterState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    func ensureConnected() async throws {
        lock.lock(); connectCalls += 1; lock.unlock()
        if case .connectThrows(let e) = nextFailures.first {
            lock.lock(); nextFailures.removeFirst(); lock.unlock()
            throw e
        }
        lock.lock(); _state = .connected(name: "MockPeriPage"); lock.unlock()
    }

    func send(_ payload: Data, jobId: UUID) async throws {
        if case .sendThrows(let e) = nextFailures.first {
            lock.lock(); nextFailures.removeFirst(); lock.unlock()
            throw e
        }
        lock.lock()
        sends.append((jobId, payload.count))
        _state = .sending(jobId: jobId, progress: 1.0)
        lock.unlock()
    }

    func disconnect() async {
        lock.lock(); disconnectCalls += 1; _state = .disconnected; lock.unlock()
    }
}
