import Foundation
import Observation

public struct LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let level: Level
    public let message: String

    public enum Level: String, Sendable {
        case info, warn, error
    }
}

@MainActor
@Observable
public final class DebugLog {
    public static let shared = DebugLog()
    public private(set) var entries: [LogEntry] = []
    private let capacity = 200

    public func info(_ msg: String)  { append(.info, msg) }
    public func warn(_ msg: String)  { append(.warn, msg) }
    public func error(_ msg: String) { append(.error, msg) }

    private func append(_ level: LogEntry.Level, _ msg: String) {
        entries.append(LogEntry(timestamp: Date(), level: level, message: msg))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    public func renderText() -> String {
        let f = ISO8601DateFormatter()
        return entries.map { "\(f.string(from: $0.timestamp))  [\($0.level.rawValue)]  \($0.message)" }
            .joined(separator: "\n")
    }
}
