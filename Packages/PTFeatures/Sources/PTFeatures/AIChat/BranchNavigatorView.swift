import SwiftUI
import PTUI

/// Shows "< 1/3 >" navigation control for message variants (conversation branches).
///
/// Visible only when a user turn has more than one AI response variant.
struct BranchNavigatorView: View {
    let currentIndex: Int
    let totalCount: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        if totalCount > 1 {
            HStack(spacing: AppSpacing.md) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                }
                .disabled(currentIndex == 0)

                Text("\(currentIndex + 1) / \(totalCount)")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                    .monospacedDigit()

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .disabled(currentIndex >= totalCount - 1)
            }
            .foregroundStyle(Morandi.secondaryText)
        }
    }
}
