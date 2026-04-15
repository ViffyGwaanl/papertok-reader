import SwiftUI
import PTCore
import PTReader
import PTUI

/// Presentational find bar shared by the EPUB and PDF reader hosts.
///
/// All state lives in `ReaderFindBarState`; this view only renders the field,
/// results counter, prev/next/close controls and the no-results affordance.
public struct ReaderFindBar: View {
    @Bindable private var state: ReaderFindBarState
    private let onClose: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var queryFocused: Bool

    public init(state: ReaderFindBarState, onClose: @escaping () -> Void) {
        self.state = state
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            mainRow
            if shouldShowSecondaryRow {
                counterRow
            }
            if state.hasNoResults {
                Text("reader.search.no_results")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                    .padding(.horizontal, AppSpacing.sm)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(Morandi.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Morandi.divider)
                .frame(height: 1)
        }
        .onAppear { queryFocused = true }
    }

    // MARK: - Rows

    private var mainRow: some View {
        HStack(spacing: AppSpacing.sm) {
            field
            if isCompact == false {
                counterView
                navigationButtons
            }
            closeButton
        }
    }

    private var counterRow: some View {
        HStack(spacing: AppSpacing.sm) {
            counterView
            Spacer()
            navigationButtons
        }
    }

    private var field: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Morandi.secondaryText)
            TextField(
                String(localized: "reader.search.bar.placeholder"),
                text: Binding(
                    get: { state.query },
                    set: { newValue in state.scheduleSubmit(query: newValue) }
                )
            )
            .focused($queryFocused)
            .textFieldStyle(.plain)
            .submitLabel(.search)
            .onSubmit {
                Task { await state.submit(query: state.query) }
            }
            if state.isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if state.query.isEmpty == false {
                Button {
                    state.clear()
                    queryFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Morandi.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "reader.search.clear"))
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(
            Morandi.divider.opacity(0.3),
            in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
        )
    }

    @ViewBuilder
    private var counterView: some View {
        if state.hits.isEmpty {
            EmptyView()
        } else {
            Text(
                AppLocalization.format(
                    "reader.search.results.count_format",
                    locale: .autoupdatingCurrent,
                    state.currentIndex + 1,
                    state.hits.count
                )
            )
            .font(AppTypography.caption)
            .foregroundStyle(Morandi.secondaryText)
            .monospacedDigit()
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: AppSpacing.xs) {
            Button {
                state.previous()
            } label: {
                Image(systemName: "chevron.up")
                    .foregroundStyle(Morandi.accent)
            }
            .buttonStyle(.plain)
            .disabled(state.hits.isEmpty)
            .accessibilityLabel(String(localized: "reader.search.prev"))

            Button {
                state.next()
            } label: {
                Image(systemName: "chevron.down")
                    .foregroundStyle(Morandi.accent)
            }
            .buttonStyle(.plain)
            .disabled(state.hits.isEmpty)
            .accessibilityLabel(String(localized: "reader.search.next"))
        }
    }

    private var closeButton: some View {
        Button {
            state.clear()
            onClose()
        } label: {
            Image(systemName: "xmark")
                .foregroundStyle(Morandi.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "common.close"))
    }

    // MARK: - Layout helpers

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var shouldShowSecondaryRow: Bool {
        isCompact && state.hits.isEmpty == false
    }
}
