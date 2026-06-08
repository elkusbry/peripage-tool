import SwiftUI
import PhotosUI

struct HomeView: View {
    @Environment(PrinterClient.self) private var printer
    @Environment(PrintQueue.self) private var queue

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pickedData: Data?                // populated only for the 1-photo path
    @State private var batchPresentation: BatchPresentation?  // non-nil presents the batch sheet
    @State private var showDebug = false
    @State private var showQueue = false

    var body: some View {
        VStack(spacing: 24) {
            StatusPill(
                state: printer.state,
                queueCount: queue.jobs.filter { !$0.status.isTerminal }.count,
                onLongPress: { showDebug = true }
            )
            .padding(.top)

            Spacer()

            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: 20,
                selectionBehavior: .ordered,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Choose Photos", systemImage: "photo.on.rectangle")
                    .font(.title2.bold())
                    .padding(.horizontal, 24).padding(.vertical, 16)
                    .background(Capsule().fill(.tint))
                    .foregroundStyle(.white)
            }

            if queue.jobs.contains(where: { !$0.status.isTerminal }) {
                Button {
                    showQueue = true
                } label: {
                    Label("Queue (\(queue.jobs.filter { !$0.status.isTerminal }.count))",
                          systemImage: "list.bullet")
                }
            }

            Spacer()

            LogTail()
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .padding()
        .navigationDestination(isPresented: Binding(
            get: { pickedData != nil },
            set: { if !$0 { pickedData = nil; photoItems = [] } }
        )) {
            if let data = pickedData {
                PreviewView(sourceData: data)
            }
        }
        .sheet(item: $batchPresentation, onDismiss: { photoItems = [] }) { presentation in
            BatchReviewView(items: presentation.items)
        }
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(isPresented: $showDebug) { DebugLogView() }
        .task(id: photoItems) {
            // Route by selection count. Empty = no-op (picker cancelled or state reset).
            switch photoItems.count {
            case 0:
                return
            case 1:
                pickedData = try? await photoItems[0].loadTransferable(type: Data.self)
            default:
                batchPresentation = BatchPresentation(items: photoItems)
            }
        }
    }
}

private struct BatchPresentation: Identifiable {
    let id = UUID()
    let items: [PhotosPickerItem]
}

private struct LogTail: View {
    @State private var entries: [LogEntry] = []
    private let log = DebugLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(entries.suffix(3)) { e in
                Text("\(e.level.rawValue.uppercased()) \(e.message)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(e.level == .error ? .red : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            // Poll the log every 250ms — cheap, no Observation setup needed for a fixed-size buffer.
            while !Task.isCancelled {
                entries = log.entries
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}
