import SwiftUI

struct CaptureView: View {
    @State private var capture = CaptureClient()
    @State private var shareURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                statusCard

                instructions

                bytesView

                Spacer()

                controls
            }
            .padding()
            .navigationTitle("BLE Capture")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                #else
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                #endif
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text(stateLabel).font(.headline)
            }
            Text(capture.statusLine).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How to capture").font(.subheadline.bold())
            Text("""
                1. Power the real Peripage **off** (or forget it in iOS Bluetooth settings).
                2. Tap Start below.
                3. Open the official Peripage app → pick any photo → Print.
                4. Watch the byte counter climb. Tap Stop once it stops moving.
                5. Tap Share to export the .bin file.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(.gray.opacity(0.08)))
    }

    private var bytesView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Captured").font(.caption).foregroundStyle(.secondary)
            Text("\(capture.captured.count) bytes")
                .font(.system(.title, design: .monospaced))
                .contentTransition(.numericText())
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            switch capture.state {
            case .idle, .stopped, .bluetoothNotReady:
                Button {
                    capture.start()
                } label: {
                    Label("Start capture", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .advertising, .connected:
                Button {
                    capture.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }

            HStack {
                Button("Clear") { capture.clear() }
                    .disabled(capture.captured.isEmpty)
                Spacer()
                if let url = shareURL {
                    ShareLink(item: url) {
                        Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        shareURL = capture.exportURL()
                    } label: {
                        Label("Prepare share", systemImage: "doc.fill.badge.plus")
                    }
                    .disabled(capture.captured.isEmpty)
                }
            }
            .font(.subheadline)
        }
    }

    private var statusColor: Color {
        switch capture.state {
        case .idle: return .secondary
        case .bluetoothNotReady: return .red
        case .advertising: return .yellow
        case .connected: return .green
        case .stopped: return .blue
        }
    }

    private var stateLabel: String {
        switch capture.state {
        case .idle: return "Idle"
        case .bluetoothNotReady(let reason): return "Bluetooth: \(reason)"
        case .advertising: return "Advertising"
        case .connected(let n): return "Connected by \(n)"
        case .stopped: return "Stopped"
        }
    }
}
