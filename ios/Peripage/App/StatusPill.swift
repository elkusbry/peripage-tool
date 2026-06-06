import SwiftUI

struct StatusPill: View {
    let state: PrinterState
    let queueCount: Int
    var onLongPress: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.callout.monospaced())
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(.thinMaterial))
        .onLongPressGesture(minimumDuration: 0.6) { onLongPress() }
    }

    private var color: Color {
        switch state {
        case .disconnected: return .secondary
        case .scanning, .connecting: return .yellow
        case .connected: return .green
        case .sending: return .blue
        case .error: return .red
        }
    }

    private var label: String {
        switch state {
        case .disconnected:
            return queueCount > 0 ? "Idle · \(queueCount) queued" : "Idle"
        case .scanning: return "Scanning…"
        case .connecting(let n): return "Connecting \(n)…"
        case .connected(let n):
            return queueCount > 0 ? "\(n) · \(queueCount) queued" : n
        case .sending(_, let p):
            return "Sending… \(Int(p * 100))%"
        case .error(let e): return "Error: \(String(describing: e))"
        }
    }
}
