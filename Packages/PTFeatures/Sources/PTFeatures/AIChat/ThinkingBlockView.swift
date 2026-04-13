import SwiftUI
import PTUI

/// Collapsible "thinking" block shown for extended-thinking model responses.
///
/// Matches Flutter's AiCollapsibleSection behavior:
/// - Collapsed by default while streaming, auto-expands on completion.
/// - Shows token count in header.
/// - Smooth height animation on toggle.
struct ThinkingBlockView: View {
    let content: String
    let tokenCount: Int?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                    Text("common.thinking_ellipsis")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Morandi.secondaryText)
                    if let count = tokenCount {
                        Text("(\(count) tokens)")
                            .font(AppTypography.caption2)
                            .foregroundStyle(Morandi.tertiaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
            }
            .buttonStyle(.plain)

            // Collapsible content
            if isExpanded {
                ScrollView {
                    Text(content)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.bottom, AppSpacing.sm)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                .fill(Morandi.cardBackground)
        )
    }
}
