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
        VStack(spacing: 12) {
            slider("Brightness", value: $adjustments.brightness, range: 0.5...2.0, step: 0.05)
            slider("Contrast",   value: $adjustments.contrast,   range: 0.5...2.0, step: 0.05)
            intSlider("Top margin",    value: $adjustments.topMarginPx,    range: 0...300, step: 5)
            intSlider("Bottom margin", value: $adjustments.bottomMarginPx, range: 0...300, step: 5)
            rotationPicker
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit()).frame(width: 50, alignment: .trailing)
        }
    }

    private func intSlider(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int.Stride) -> some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(
                value: Binding(get: { Double(value.wrappedValue) },
                               set: { value.wrappedValue = Int($0) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step)
            )
            Text("\(value.wrappedValue) px")
                .font(.caption.monospacedDigit()).frame(width: 50, alignment: .trailing)
        }
    }

    private var rotationPicker: some View {
        HStack {
            Text("Rotation").frame(width: 110, alignment: .leading)
            Picker("", selection: $adjustments.rotation) {
                ForEach(Rotation.allCases, id: \.self) { r in
                    Text(r.label).tag(r)
                }
            }.pickerStyle(.segmented)
        }
    }

    private var buttons: some View {
        HStack {
            Button("Add to queue") {
                queue.enqueue(PrintJob(sourceData: sourceData, adjustments: adjustments))
                dismiss()
            }.buttonStyle(.bordered)

            Spacer()

            Button("Print now") {
                queue.enqueue(PrintJob(sourceData: sourceData, adjustments: adjustments))
                queue.start()
                dismiss()
            }.buttonStyle(.borderedProminent)
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
