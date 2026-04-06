import SwiftUI
import PTUI

/// Filter bar for Papers page: search field, liked-only toggle chip, and date filter chips.
struct PapersFilterBar: View {
    @Binding var searchQuery: String
    @Binding var likedOnly: Bool
    @Binding var dayFilter: String
    let onRefresh: () -> Void

    private let dayOptions: [(label: String, value: String)] = [
        ("Latest", "latest"),
        ("All", "all"),
    ]

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            PTSearchBar(text: $searchQuery, placeholder: "Search papers...")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    FilterChip(
                        label: "Liked",
                        icon: "heart.fill",
                        isSelected: likedOnly
                    ) { likedOnly.toggle() }

                    Divider().frame(height: 20)

                    ForEach(dayOptions, id: \.value) { option in
                        FilterChip(
                            label: option.label,
                            isSelected: dayFilter == option.value
                        ) { dayFilter = option.value }
                    }

                    Spacer(minLength: AppSpacing.xs)

                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundStyle(Morandi.secondaryText)
                    }
                    .buttonStyle(.bordered)
                    .tint(Morandi.secondaryText)
                }
                .padding(.horizontal, AppSpacing.lg)
            }
        }
        .padding(.vertical, AppSpacing.sm)
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(AppTypography.caption)
                }
                Text(label)
                    .font(AppTypography.caption.weight(.medium))
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 6)
            .background(isSelected ? Morandi.accent : Morandi.divider.opacity(0.5))
            .foregroundStyle(isSelected ? .white : Morandi.primaryText)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
