import SwiftUI
import Charts
import PTCore
import PTAIServices
import PTUI

/// Dashboard showing AI token usage statistics.
public struct UsageDashboardView: View {
    @State private var viewModel: UsageDashboardViewModel
    @State private var showClearConfirmation = false

    @MainActor
    public init(tracker: UsageTracker) {
        _viewModel = State(initialValue: UsageDashboardViewModel(tracker: tracker))
    }

    public var body: some View {
        List {
            summarySection
            perModelSection
            dailyChartSection
            clearSection
        }
        .scrollContentBackground(.hidden)
        .background(Morandi.background)
        .navigationTitle(String(localized: "settings.usage.section"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await viewModel.loadData()
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            summaryRow(
                String(localized: "settings.usage.total"),
                value: viewModel.totalAllTime
            )
            summaryRow(
                String(localized: "settings.usage.today"),
                value: viewModel.totalToday
            )
            summaryRow(
                String(localized: "settings.usage.this_week"),
                value: viewModel.totalThisWeek
            )
            summaryRow(
                String(localized: "settings.usage.this_month"),
                value: viewModel.totalThisMonth
            )
        } header: {
            Text("settings.usage.section")
        }
    }

    private func summaryRow(_ title: String, value: Int) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Morandi.primaryText)
            Spacer()
            Text(formatNumber(value))
                .foregroundStyle(Morandi.secondaryText)
                .monospacedDigit()
        }
    }

    // MARK: - Per-Model Breakdown

    private var perModelSection: some View {
        Section {
            if viewModel.perModelBreakdown.isEmpty {
                Text("settings.usage.no_data")
                    .foregroundStyle(Morandi.tertiaryText)
            } else {
                ForEach(viewModel.perModelBreakdown) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.modelId)
                            .font(AppTypography.subheadline.weight(.medium))
                            .foregroundStyle(Morandi.primaryText)
                        HStack(spacing: AppSpacing.lg) {
                            labeledValue(
                                String(localized: "settings.usage.per_model.prompt"),
                                value: entry.promptTokens
                            )
                            labeledValue(
                                String(localized: "settings.usage.per_model.completion"),
                                value: entry.completionTokens
                            )
                            labeledValue(
                                String(localized: "settings.usage.per_model.calls"),
                                value: entry.callCount
                            )
                        }
                        .font(AppTypography.caption2)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("settings.usage.per_model.title")
        }
    }

    private func labeledValue(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .foregroundStyle(Morandi.tertiaryText)
            Text(formatNumber(value))
                .foregroundStyle(Morandi.secondaryText)
                .monospacedDigit()
        }
    }

    // MARK: - Daily Chart

    private var dailyChartSection: some View {
        Section {
            if viewModel.dailyData.isEmpty {
                Text("settings.usage.no_data")
                    .foregroundStyle(Morandi.tertiaryText)
            } else {
                Chart {
                    ForEach(viewModel.dailyData) { day in
                        BarMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Tokens", day.promptTokens)
                        )
                        .foregroundStyle(Morandi.sage)

                        BarMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Tokens", day.completionTokens)
                        )
                        .foregroundStyle(Morandi.lavender)
                    }
                }
                .chartForegroundStyleScale([
                    String(localized: "settings.usage.per_model.prompt"): Morandi.sage,
                    String(localized: "settings.usage.per_model.completion"): Morandi.lavender,
                ])
                .frame(height: 180)
                .padding(.vertical, AppSpacing.sm)
            }
        } header: {
            Text("settings.usage.daily_chart.title")
        }
    }

    // MARK: - Clear

    private var clearSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Text("settings.usage.clear_button")
            }
            .confirmationDialog(
                String(localized: "settings.usage.clear_confirm.title"),
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "settings.usage.clear_button"), role: .destructive) {
                    Task {
                        await viewModel.purgeData()
                    }
                }
            } message: {
                Text("settings.usage.clear_confirm.message")
            }
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
