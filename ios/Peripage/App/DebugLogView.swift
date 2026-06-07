import SwiftUI

struct DebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showCapture = false
    private let log = DebugLog.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(log.renderText())
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
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
}
