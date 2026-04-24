import SwiftUI
import PTReader
import PTUI

/// Horizontal row of Morandi-tinted color dots for choosing a highlight color.
/// Tapping a dot invokes the `onSelect` callback with the chosen color.
struct HighlightColorPicker: View {
    let selected: HighlightColor
    let onSelect: (HighlightColor) -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button {
                    onSelect(color)
                } label: {
                    ZStack {
                        Circle()
                            .fill(morandiColor(for: color))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(
                                        selected == color
                                            ? Morandi.accent
                                            : Color.clear,
                                        lineWidth: selected == color ? 2 : 0
                                    )
                            )

                        if selected == color {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(color.rawValue.capitalized))
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private func morandiColor(for color: HighlightColor) -> Color {
        switch color {
        case .yellow: return Morandi.highlightYellow
        case .red:    return Morandi.highlightRed
        case .blue:   return Morandi.highlightBlue
        case .green:  return Morandi.highlightGreen
        case .purple: return Morandi.highlightPurple
        }
    }
}
