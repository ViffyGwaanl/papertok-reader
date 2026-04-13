import SwiftUI
import PTUI

/// Filter bar for Papers page: search field, liked-only toggle chip, and date filter chips.
struct PapersFilterBar: View {
    @Binding var searchQuery: String
    @Binding var likedOnly: Bool
    @Binding var dayFilter: String
    @Binding var language: String
    @Binding var customDate: Date?
    let onRefresh: () -> Void

    @State private var isShowingDatePicker = false
    @State private var draftDate = Date()

    private var dayOptions: [(label: String, value: String)] {
        [
            (String(localized: "papers.filter.latest"), "latest"),
            (String(localized: "papers.filter.all"), "all"),
        ]
    }

    private let languageOptions: [(label: String, value: String)] = [
        ("ZH", "zh"),
        ("EN", "en"),
    ]

    private var isCustomDateSelected: Bool {
        customDate != nil && dayFilter != "latest" && dayFilter != "all"
    }

    private var customDateLabel: String {
        guard let customDate else { return String(localized: "papers.pick_a_date") }
        return customDate.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            PTSearchBar(text: $searchQuery, placeholder: String(localized: "papers.search_placeholder"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(languageOptions, id: \.value) { option in
                        FilterChip(
                            label: option.label,
                            isSelected: language == option.value
                        ) { language = option.value }
                    }

                    Divider().frame(height: 20)

                    FilterChip(
                        label: String(localized: "papers.filter.liked"),
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

                    FilterChip(
                        label: customDateLabel,
                        icon: isCustomDateSelected ? "calendar.badge.checkmark" : "calendar",
                        isSelected: isCustomDateSelected
                    ) {
                        draftDate = customDate ?? Date()
                        isShowingDatePicker = true
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
        .sheet(isPresented: $isShowingDatePicker) {
            NavigationStack {
                VStack(spacing: AppSpacing.lg) {
                    DatePicker(
                        String(localized: "papers.date_label"),
                        selection: $draftDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                    HStack(spacing: AppSpacing.md) {
                        Button(String(localized: "common.cancel")) {
                            isShowingDatePicker = false
                        }
                        .buttonStyle(.bordered)

                        Button(String(localized: "common.apply")) {
                            customDate = draftDate
                            isShowingDatePicker = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Morandi.accent)
                    }
                }
                .padding(AppSpacing.lg)
                .navigationTitle(String(localized: "papers.pick_a_date"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        }
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
