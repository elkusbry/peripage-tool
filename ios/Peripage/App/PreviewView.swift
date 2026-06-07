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
            buttonGroup(
                "Brightness",
                options: BrightnessLevel.allCases,
                isSelected: { BrightnessLevel.from(adjustments.brightness) == $0 },
                onSelect: { adjustments.brightness = $0.value }
            )
            buttonGroup(
                "Contrast",
                options: ContrastLevel.allCases,
                isSelected: { ContrastLevel.from(adjustments.contrast) == $0 },
                onSelect: { adjustments.contrast = $0.value }
            )
            buttonGroup(
                "Rotation",
                options: RotationOption.allCases,
                isSelected: { $0 == RotationOption.from(adjustments.rotation) },
                onSelect: { adjustments.rotation = $0.rotation }
            )
        }
    }

    private func buttonGroup<T: AdjustmentOption>(
        _ title: String,
        options: [T],
        isSelected: @escaping (T) -> Bool,
        onSelect: @escaping (T) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { opt in
                    let selected = isSelected(opt)
                    Button {
                        onSelect(opt)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: opt.icon).font(.title3)
                            Text(opt.label).font(.caption2)
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

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                queue.enqueue(PrintJob(sourceData: sourceData, adjustments: adjustments))
                queue.start()
                dismiss()
            } label: {
                Label("Print", systemImage: "printer.fill")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
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

// MARK: - Adjustment option model

protocol AdjustmentOption: Hashable {
    var label: String { get }
    var icon: String { get }
}

enum BrightnessLevel: String, CaseIterable, AdjustmentOption {
    case dim, normal, bright

    var value: Double {
        switch self {
        case .dim:    return 0.8
        case .normal: return 1.0
        case .bright: return 1.4
        }
    }
    var label: String {
        switch self {
        case .dim:    return "Dim"
        case .normal: return "Normal"
        case .bright: return "Bright"
        }
    }
    var icon: String {
        switch self {
        case .dim:    return "sun.min"
        case .normal: return "sun.max"
        case .bright: return "sun.max.fill"
        }
    }
    static func from(_ v: Double) -> BrightnessLevel {
        BrightnessLevel.allCases.min(by: { abs($0.value - v) < abs($1.value - v) }) ?? .normal
    }
}

enum ContrastLevel: String, CaseIterable, AdjustmentOption {
    case soft, normal, bold

    var value: Double {
        switch self {
        case .soft:   return 0.9
        case .normal: return 1.2
        case .bold:   return 1.7
        }
    }
    var label: String {
        switch self {
        case .soft:   return "Soft"
        case .normal: return "Normal"
        case .bold:   return "Bold"
        }
    }
    var icon: String {
        switch self {
        case .soft:   return "circle.dotted"
        case .normal: return "circle.lefthalf.filled"
        case .bold:   return "circle.fill"
        }
    }
    static func from(_ v: Double) -> ContrastLevel {
        ContrastLevel.allCases.min(by: { abs($0.value - v) < abs($1.value - v) }) ?? .normal
    }
}

enum RotationOption: String, CaseIterable, AdjustmentOption {
    case auto, landscape, portrait

    var rotation: Rotation {
        switch self {
        case .auto:      return .auto
        case .landscape: return .deg0
        case .portrait:  return .deg90
        }
    }
    var label: String {
        switch self {
        case .auto:      return "Auto"
        case .landscape: return "Landscape"
        case .portrait:  return "Portrait"
        }
    }
    var icon: String {
        switch self {
        case .auto:      return "wand.and.stars"
        case .landscape: return "rectangle"
        case .portrait:  return "rectangle.portrait"
        }
    }
    static func from(_ r: Rotation) -> RotationOption {
        switch r {
        case .deg0:           return .landscape
        case .deg90:          return .portrait
        case .auto, .deg180, .deg270: return .auto
        }
    }
}
