import SwiftUI

struct PreviewView: View {
    let sourceData: Data
    @Environment(PrintQueue.self) private var queue
    @Environment(\.dismiss) private var dismiss

    @State private var adjustments = Adjustments.default
    @State private var preview: PlatformImage?
    @State private var renderError: String?

    var body: some View {
        VStack(spacing: 16) {
            previewPane
                .frame(maxWidth: .infinity, maxHeight: 360)
                .background(
                    checkerboard
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                )

            controls
            buttons
        }
        .padding()
        .navigationTitle("Adjust")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: adjustments) {
            await rerenderDebounced()
        }
    }

    private var previewPane: some View {
        Group {
            if let preview {
                #if canImport(UIKit)
                Image(uiImage: preview).resizable().interpolation(.none).scaledToFit()
                #else
                Image(nsImage: preview).resizable().interpolation(.none).scaledToFit()
                #endif
            } else if let renderError {
                Text(renderError).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
    }

    private var controls: some View {
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

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                queue.enqueue(PrintJob(sourceData: sourceData, adjustments: adjustments))
                queue.start()
                dismiss()
            } label: {
                Label("Print", systemImage: "printer.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Add to queue") {
                queue.enqueue(PrintJob(sourceData: sourceData, adjustments: adjustments))
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var checkerboard: some View {
        Canvas { ctx, size in
            let s: CGFloat = 12
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) {
                    let dark = (Int(x/s) + Int(y/s)) % 2 == 0
                    ctx.fill(
                        Path(CGRect(x: x, y: y, width: s, height: s)),
                        with: .color(dark ? .gray.opacity(0.18) : .gray.opacity(0.08))
                    )
                }
            }
        }
    }

    private func rerenderDebounced() async {
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }
        do {
            let processed = try ImageProcessor.process(sourceData, adjustments: adjustments)
            #if canImport(UIKit)
            preview = UIImage(cgImage: processed.previewCGImage)
            #else
            preview = NSImage(cgImage: processed.previewCGImage, size: NSSize(width: processed.width, height: processed.height))
            #endif
            renderError = nil
        } catch {
            renderError = String(describing: error)
        }
    }
}

// Adjustment levels + the button-group view moved to Peripage/SharedUI/
// so the share extension can use them too.
