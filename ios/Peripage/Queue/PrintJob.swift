import Foundation

public enum JobStatus: Equatable, Sendable {
    case pending
    case rendering
    case sending(progress: Double)
    case done
    case failed(reason: String)

    public var isTerminal: Bool {
        switch self {
        case .done, .failed: return true
        default: return false
        }
    }
}

public struct PrintJob: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceData: Data
    public var adjustments: Adjustments
    public var status: JobStatus

    public init(
        id: UUID = UUID(),
        sourceData: Data,
        adjustments: Adjustments,
        status: JobStatus = .pending
    ) {
        self.id = id
        self.sourceData = sourceData
        self.adjustments = adjustments
        self.status = status
    }
}
