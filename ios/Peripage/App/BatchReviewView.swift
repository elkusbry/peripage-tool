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
    @State private var batchRotation: BatchRotation = .auto

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
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
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.15))
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    switch entry.state {
                    case .loading:
                        ProgressView()
                    case .ready(let image, _):
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    case .failed:
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }

            Text("\(index + 1)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.black.opacity(0.7)))
                .padding(8)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        remove(entry.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.7))
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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

        return VStack(spacing: 10) {
            Picker("Orientation", selection: $batchRotation) {
                ForEach(BatchRotation.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Button {
                printAll()
            } label: {
                Text(label)
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(.tint))
                    .foregroundStyle(.white)
                    .padding(.horizontal)
            }
            .disabled(anyLoading || readyCount == 0)
        }
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Actions

    private func loadAll() async {
        // Seed entries up front so the grid renders placeholders immediately.
        if entries.isEmpty {
            entries = items.map { BatchEntry(pickerItem: $0) }
        }

        // Sequential on the MainActor: PhotosPickerItem.loadTransferable can stall when
        // invoked from detached child tasks, and serial loading also keeps memory bounded
        // (one full-resolution decode in flight at a time).
        for entry in entries {
            let state: BatchEntry.State
            do {
                if let data = try await entry.pickerItem.loadTransferable(type: Data.self),
                   let image = downscaled(data: data) {
                    state = .ready(thumb: image, data: data)
                } else {
                    state = .failed
                }
            } catch {
                state = .failed
            }
            if let i = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[i].state = state
            }
        }
    }

    private func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    private func printAll() {
        for entry in entries {
            if case .ready(let thumb, let data) = entry.state {
                let rotation = batchRotation.resolved(forLandscape: thumb.size.width > thumb.size.height)
                queue.enqueue(PrintJob(sourceData: data, adjustments: Adjustments(rotation: rotation)))
            }
        }
        queue.start()
        dismiss()
    }
}

// MARK: - Batch rotation mode

private enum BatchRotation: String, CaseIterable, Identifiable, Hashable {
    case auto, vertical, horizontal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        }
    }

    /// Resolve to a per-image Rotation. Vertical = long edge along paper feed
    /// (image prints tall). Horizontal = short edge along feed (image prints wide).
    /// Rotate counter-clockwise when reorienting — matches iOS Photos' "Rotate" default.
    func resolved(forLandscape isLandscape: Bool) -> Rotation {
        switch self {
        case .auto:
            return .auto
        case .vertical:
            return isLandscape ? .deg270 : .deg0
        case .horizontal:
            return isLandscape ? .deg0 : .deg270
        }
    }
}

// MARK: - Model

private struct BatchEntry: Identifiable {
    let id = UUID()
    let pickerItem: PhotosPickerItem
    var state: State = .loading

    // Not Equatable on purpose: a custom == by id alone makes SwiftUI's
    // view-diffing think state mutations are no-ops, so tiles stay stuck
    // on the loading spinner. Without Equatable, every @State write
    // forces a fresh render.
    enum State {
        case loading
        case ready(thumb: UIImage, data: Data)
        case failed
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
