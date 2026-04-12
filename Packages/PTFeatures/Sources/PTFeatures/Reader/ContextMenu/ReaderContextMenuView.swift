import SwiftUI
import PTCore
import PTReader
import PTUI

/// Floating context menu that appears near selected text in the reader.
///
/// Layout:
/// - Top row: highlight color dots (tap to highlight immediately)
/// - Bottom rows: action buttons grouped by category
/// - Morandi card styling with shadow
struct ReaderContextMenuView: View {
    @Bindable var coordinator: ContextMenuCoordinator
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            // Highlight color row
            VStack(spacing: AppSpacing.xs) {
                Text("Highlight")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HighlightColorPicker(
                    selected: coordinator.highlightColor,
                    onSelect: { color in
                        coordinator.highlightColor = color
                        coordinator.handleAction(.highlight)
                        onDismiss()
                    }
                )
            }

            Divider()
                .background(Morandi.divider)

            // Action buttons
            actionGrid
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                .fill(Morandi.cardBackground)
                .shadow(color: .black.opacity(0.12), radius: AppSpacing.shadowRadius, x: 0, y: 2)
        )
        .frame(maxWidth: 320)
    }

    private var actionGrid: some View {
        let actions: [ContextMenuAction] = [
            .note, .copy, .translate, .explain, .summarize, .define, .search, .share
        ]

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.xs), count: 4),
            spacing: AppSpacing.sm
        ) {
            ForEach(actions) { action in
                Button {
                    coordinator.handleAction(action)
                    // Some actions open sheets rather than dismissing immediately
                    switch action {
                    case .copy, .highlight, .search:
                        onDismiss()
                    default:
                        break
                    }
                } label: {
                    VStack(spacing: AppSpacing.xs) {
                        Image(systemName: action.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(iconColor(for: action))
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                                    .fill(iconColor(for: action).opacity(0.1))
                            )

                        Text(action.title)
                            .font(AppTypography.caption)
                            .foregroundStyle(Morandi.primaryText)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func iconColor(for action: ContextMenuAction) -> Color {
        switch action.category {
        case .annotate: return Morandi.dustyRose
        case .ai:       return Morandi.sage
        case .utility:  return Morandi.powder
        }
    }
}
