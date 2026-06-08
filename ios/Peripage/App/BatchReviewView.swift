// ios/Peripage/App/BatchReviewView.swift
import SwiftUI
import PhotosUI
import ImageIO

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
                        Image(platformImage: image)
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
        let printLabel = readyCount == 0 ? "Print all" : "Print all \(readyCount)"
        let queueLabel = readyCount == 0 ? "Add all to queue" : "Add all \(readyCount) to queue"
        let disabled = anyLoading || readyCount == 0

        return VStack(spacing: 12) {
            rotationButtonGroup

            Button {
                printAll(start: true)
            } label: {
                Label(printLabel, systemImage: "printer.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(disabled)

            Button(queueLabel) {
                printAll(start: false)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(disabled)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var rotationButtonGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rotation").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(BatchRotation.allCases) { mode in
                    let selected = mode == batchRotation
                    Button {
                        batchRotation = mode
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: mode.icon).font(.title3)
                            Text(mode.label).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selected ? Color.accentColor.opacity(0.20) : Color.gray.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                        .foregroundStyle(selected ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

    private func printAll(start: Bool) {
        for (idx, entry) in entries.enumerated() {
            if case .ready(let thumb, let data) = entry.state {
                let isLandscape = thumb.size.width > thumb.size.height
                let rotation = batchRotation.resolved(forLandscape: isLandscape)
                DebugLog.shared.info(
                    "Batch[\(idx + 1)]: thumb=\(Int(thumb.size.width))×\(Int(thumb.size.height)) " +
                    "landscape=\(isLandscape) mode=\(batchRotation.label) → rotation=\(rotation.label)"
                )
                queue.enqueue(PrintJob(sourceData: data, adjustments: Adjustments(rotation: rotation)))
            }
        }
        if start { queue.start() }
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

    var icon: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .vertical: return "rectangle.portrait"
        case .horizontal: return "rectangle"
        }
    }

    /// Resolve to a per-image Rotation. CCW reorient when needed —
    /// matches iOS Photos' "Rotate" default direction.
    /// Currently identical for landscape and portrait sources per user
    /// testing: Vertical leaves the photo as-is (long edge runs down the
    /// strip), Horizontal rotates 90° CCW (long edge runs across the
    /// strip). `forLandscape` is kept on the signature so we can
    /// re-introduce orientation-aware logic without a churning refactor.
    func resolved(forLandscape isLandscape: Bool) -> Rotation {
        _ = isLandscape
        switch self {
        case .auto:       return .auto
        case .vertical:   return .deg0
        case .horizontal: return .deg270
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
        case ready(thumb: PlatformImage, data: Data)
        case failed
    }
}

// MARK: - Helpers

/// Decode `data` and downscale to ~600px on the long edge for grid display
/// using ImageIO so it works on both iOS and macOS.
private func downscaled(data: Data) -> PlatformImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: 600,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    #if canImport(UIKit)
    return UIImage(cgImage: cg)
    #else
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    #endif
}
