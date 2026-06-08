import SwiftUI

/// The pill-button group used for Brightness / Contrast / Rotation pickers
/// in both PreviewView (host app) and ShareRootView (share extension).
/// Single source of truth — change the look here, both surfaces update.
struct AdjustmentButtonGroup<T: AdjustmentOption>: View {
    let title: String
    let options: [T]
    let isSelected: (T) -> Bool
    let onSelect: (T) -> Void

    var body: some View {
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
}
