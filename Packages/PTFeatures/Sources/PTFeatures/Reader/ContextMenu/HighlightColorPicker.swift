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
                            .frame(width: 30, height: 30)

                        if selected == color {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(color.rawValue.capitalized))
            }
        }
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
