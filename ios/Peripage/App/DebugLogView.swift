import SwiftUI

struct DebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PrinterClient.self) private var printer
    @Environment(PrintQueue.self) private var queue
    @State private var showCapture = false
    private let log = DebugLog.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    deviceSection
                    Divider()
                    Text(log.renderText())
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle("Debug Log")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                #else
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                #endif
                ToolbarItem {
                    ShareLink(item: log.renderText()) { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItem {
                    Button {
                        showCapture = true
                    } label: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                }
            }
            .sheet(isPresented: $showCapture) { CaptureView() }
        }
    }

    private var deviceSection: some View {
        let pending = queue.jobs.filter { $0.status == .pending }.count
        let done = queue.jobs.filter { $0.status == .done }.count
        let failed = queue.jobs.filter { if case .failed = $0.status { return true } else { return false } }.count
        let warns = log.entries.filter { $0.level == .warn }.count
        let errs = log.entries.filter { $0.level == .error }.count

        return VStack(alignment: .leading, spacing: 4) {
            Text("Device")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            row("State", stateLabel(printer.state))
            row("Device", deviceLabel(printer.state))
            row("Queue", "\(pending) pending · \(done) done · \(failed) failed")
            row("Log", "\(log.entries.count) entries · \(warns) warn · \(errs) err")
        }
        .font(.system(.caption, design: .monospaced))
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func stateLabel(_ state: PrinterState) -> String {
        switch state {
        case .disconnected:           return "disconnected"
        case .scanning:               return "scanning"
        case .connecting:             return "connecting"
        case .connected:              return "connected"
        case .sending(_, let p):      return "sending \(Int(p * 100))%"
        case .error(let e):           return "error · \(String(describing: e))"
        }
    }

    private func deviceLabel(_ state: PrinterState) -> String {
        switch state {
        case .connecting(let name), .connected(let name): return name
        default:                                          return "—"
        }
    }
}
