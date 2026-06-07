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

                slider("Brightness", value: $adjustments.brightness, range: 0.5...2.0, step: 0.05)
                slider("Contrast",   value: $adjustments.contrast,   range: 0.5...2.0, step: 0.05)
                intSlider("Top",    value: $adjustments.topMarginPx,    range: 0...300, step: 5)
                intSlider("Bottom", value: $adjustments.bottomMarginPx, range: 0...300, step: 5)

                HStack {
                    Text("Rotation").frame(width: 100, alignment: .leading)
                    Picker("", selection: $adjustments.rotation) {
                        ForEach(Rotation.allCases, id: \.self) { r in Text(r.label).tag(r) }
                    }.pickerStyle(.segmented)
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

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit()).frame(width: 50, alignment: .trailing)
        }
    }

    private func intSlider(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int.Stride) -> some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            Slider(
                value: Binding(get: { Double(value.wrappedValue) },
                               set: { value.wrappedValue = Int($0) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step)
            )
            Text("\(value.wrappedValue) px").font(.caption.monospacedDigit())
                .frame(width: 50, alignment: .trailing)
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
