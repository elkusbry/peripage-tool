import SwiftUI
import UIKit

struct ShareRootView: View {
    let inputItems: [Any]
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var sourceData: Data?
    @State private var loadError: String?
    @State private var adjustments = Adjustments.default
    @State private var preview: UIImage?
    @State private var renderError: String?

    // Single-shot printer + status
    @State private var printer = PrinterClient()
    @State private var phase: Phase = .editing

    enum Phase: Equatable {
        case editing
        case printing(progress: Double)
        case done
        case failed(reason: String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Print to Peripage")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { onCancel() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Print") { Task { await print() } }
                            .disabled(!canPrint)
                            .fontWeight(.semibold)
                    }
                }
                .task { await loadSource() }
                .task(id: adjustments) { await rerenderDebounced() }
        }
    }

    private var canPrint: Bool {
        if case .editing = phase, sourceData != nil, preview != nil { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .editing:
            editingBody
        case .printing(let p):
            VStack(spacing: 16) {
                ProgressView(value: p).progressViewStyle(.linear).padding()
                Text("Sending… \(Int(p * 100))%").font(.callout)
            }.padding()
        case .done:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("Sent to printer").font(.title3.bold())
                Button("Done") { onDone() }.buttonStyle(.borderedProminent)
            }.padding()
        case .failed(let reason):
            VStack(spacing: 12) {
                Image(systemName: "xmark.octagon.fill").font(.largeTitle).foregroundStyle(.red)
                Text("Failed").font(.title3.bold())
                Text(reason).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { onCancel() }.buttonStyle(.bordered)
                    Button("Try again") { phase = .editing }.buttonStyle(.borderedProminent)
                }
            }.padding()
        }
    }

    private var editingBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                previewPane
                    .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 320)

                VStack(spacing: 20) {
                    AdjustmentButtonGroup(
                        title: "Brightness",
                        options: BrightnessLevel.allCases,
                        isSelected: { BrightnessLevel.from(adjustments.brightness) == $0 },
                        onSelect: { adjustments.brightness = $0.value }
                    )
                    AdjustmentButtonGroup(
                        title: "Contrast",
                        options: ContrastLevel.allCases,
                        isSelected: { ContrastLevel.from(adjustments.contrast) == $0 },
                        onSelect: { adjustments.contrast = $0.value }
                    )
                    AdjustmentButtonGroup(
                        title: "Rotation",
                        options: RotationOption.allCases,
                        isSelected: { $0 == RotationOption.from(adjustments.rotation) },
                        onSelect: { adjustments.rotation = $0.rotation }
                    )
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if let preview {
            Image(uiImage: preview).resizable().interpolation(.none).scaledToFit()
        } else if let renderError {
            Text(renderError).foregroundStyle(.red)
        } else if let loadError {
            Text(loadError).foregroundStyle(.red)
        } else {
            ProgressView()
        }
    }

    // MARK: - Load + render

    private func loadSource() async {
        do {
            let data = try await SharePayload.loadFirstImage(from: inputItems)
            sourceData = data
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func rerenderDebounced() async {
        try? await Task.sleep(for: .milliseconds(150))
        guard let sourceData, !Task.isCancelled else { return }
        do {
            let processed = try ImageProcessor.process(sourceData, adjustments: adjustments)
            preview = UIImage(cgImage: processed.previewCGImage)
            renderError = nil
        } catch {
            renderError = String(describing: error)
        }
    }

    // MARK: - Print

    private func print() async {
        guard let sourceData else { return }
        phase = .printing(progress: 0)
        do {
            let processed = try ImageProcessor.process(sourceData, adjustments: adjustments)
            let payload = PeripageProtocol.buildPayload(
                rasterBytes: processed.rasterBytes,
                height: processed.height,
                leadingFeed: adjustments.topMarginPx,
                trailingFeed: adjustments.bottomMarginPx
            )
            try await printer.ensureConnected()
            let jobId = UUID()
            // Reflect printer.state progress into our local UI.
            let progressObserver = Task { @MainActor in
                while !Task.isCancelled {
                    if case .sending(_, let p) = printer.state {
                        phase = .printing(progress: p)
                    }
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
            defer { progressObserver.cancel() }
            try await printer.send(payload, jobId: jobId)
            await printer.disconnect()
            phase = .done
        } catch {
            phase = .failed(reason: String(describing: error))
        }
    }
}
