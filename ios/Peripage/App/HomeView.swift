import SwiftUI
import PhotosUI

struct HomeView: View {
    @Environment(PrinterClient.self) private var printer
    @Environment(PrintQueue.self) private var queue

    @State private var photoItem: PhotosPickerItem?
    @State private var pickedData: Data?
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

            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
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
        }
        .padding()
        .navigationDestination(isPresented: Binding(
            get: { pickedData != nil },
            set: { if !$0 { pickedData = nil; photoItem = nil } }
        )) {
            if let data = pickedData {
                PreviewView(sourceData: data)
            }
        }
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(isPresented: $showDebug) { DebugLogView() }
        .task(id: photoItem) {
            guard let photoItem else { return }
            pickedData = try? await photoItem.loadTransferable(type: Data.self)
        }
    }
}
