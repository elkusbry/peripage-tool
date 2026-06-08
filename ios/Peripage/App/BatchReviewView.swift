// ios/Peripage/App/BatchReviewView.swift
import SwiftUI
import PhotosUI

#if canImport(UIKit)
import UIKit

struct BatchReviewView: View {
    @Environment(PrintQueue.self) private var queue
    @Environment(\.dismiss) private var dismiss

    let items: [PhotosPickerItem]

    @State private var entries: [BatchEntry] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        tile(index: index, entry: entry)
                    }
                }
                .padding()
            }
            .navigationTitle("Review \(entries.count) Photo\(entries.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                printAllBar
            }
        }
        .task {
            await loadAll()
        }
    }

    // MARK: - Tiles

    @ViewBuilder
    private func tile(index: Int, entry: BatchEntry) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch entry.state {
                case .loading:
                    placeholder { ProgressView() }
                case .ready(let image, _):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                case .failed:
                    placeholder {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Numbered badge — reflects current index after any removals.
            Text("\(index + 1)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.6)))
                .padding(6)

            // × in top-trailing.
            VStack {
                HStack {
                    Spacer()
                    Button {
                        remove(entry.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.secondary.opacity(0.15)
            content()
        }
    }

    // MARK: - Bottom bar

    private var printAllBar: some View {
        let readyCount = entries.filter { if case .ready = $0.state { return true } else { return false } }.count
        let anyLoading = entries.contains { if case .loading = $0.state { return true } else { return false } }
        let label = readyCount == 0 ? "Print all" : "Print all \(readyCount)"

        return Button {
            printAll()
        } label: {
            Text(label)
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(.tint))
                .foregroundStyle(.white)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .disabled(anyLoading || readyCount == 0)
    }

    // MARK: - Actions

    private func loadAll() async {
        // Seed entries up front so the grid renders placeholders immediately.
        if entries.isEmpty {
            entries = items.map { BatchEntry(pickerItem: $0) }
        }

        await withTaskGroup(of: (UUID, BatchEntry.State).self) { group in
            for entry in entries {
                group.addTask {
                    do {
                        guard let data = try await entry.pickerItem.loadTransferable(type: Data.self) else {
                            return (entry.id, .failed)
                        }
                        guard let image = downscaled(data: data) else {
                            return (entry.id, .failed)
                        }
                        return (entry.id, .ready(thumb: image, data: data))
                    } catch {
                        return (entry.id, .failed)
                    }
                }
            }
            for await (id, state) in group {
                if let i = entries.firstIndex(where: { $0.id == id }) {
                    entries[i].state = state
                }
            }
        }
    }

    private func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    private func printAll() {
        for entry in entries {
            if case .ready(_, let data) = entry.state {
                queue.enqueue(PrintJob(sourceData: data, adjustments: .default))
            }
        }
        dismiss()
    }
}

// MARK: - Model

private struct BatchEntry: Identifiable, Equatable {
    let id = UUID()
    let pickerItem: PhotosPickerItem
    var state: State = .loading

    enum State: Equatable {
        case loading
        case ready(thumb: UIImage, data: Data)
        case failed
    }

    static func == (lhs: BatchEntry, rhs: BatchEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Helpers

/// Decode `data` and downscale to ~600pt on the long edge for grid display.
/// Returns nil if the data isn't a decodable image.
private func downscaled(data: Data) -> UIImage? {
    guard let source = UIImage(data: data) else { return nil }
    let maxEdge: CGFloat = 600
    let w = source.size.width
    let h = source.size.height
    guard max(w, h) > maxEdge else { return source }
    let scale = maxEdge / max(w, h)
    let target = CGSize(width: w * scale, height: h * scale)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: target, format: format)
    return renderer.image { _ in
        source.draw(in: CGRect(origin: .zero, size: target))
    }
}

#else

struct BatchReviewView: View {
    let items: [PhotosPickerItem]
    var body: some View { Text("Multi-photo selection is iOS-only") }
}

#endif
