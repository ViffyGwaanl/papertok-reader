import SwiftUI
import PTAIServices
import PTCore
import PTUI

/// Settings screen that lists every registered AI tool (46 total), grouped by
/// category, with toggles for enabling/disabling each tool and a picker for
/// the approval threshold governing which risk levels require user approval.
public struct AIToolsConfigView: View {
    @State private var viewModel: SettingsViewModel
    @State private var filter: Filter = .all

    private let registry: ToolRegistry

    private func localized(_ key: String) -> String {
        AppLocalization.string(key)
    }

    public enum Filter: String, CaseIterable, Identifiable {
        case all, safe, moderate, dangerous
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .all:
                AppLocalization.string("papers.filter.all")
            case .safe:
                AppLocalization.string("ai.tool_filter.safe")
            case .moderate:
                AppLocalization.string("ai.tool_filter.moderate")
            case .dangerous:
                AppLocalization.string("ai.tool_filter.dangerous")
            }
        }
    }

    @MainActor
    public init(
        viewModel: SettingsViewModel? = nil,
        registry: ToolRegistry = .default
    ) {
        _viewModel = State(initialValue: viewModel ?? SettingsViewModel())
        self.registry = registry
    }

    public var body: some View {
        Form {
            thresholdSection
            filterSection
            toolsSection
        }
        .scrollContentBackground(.hidden)
        .background(Morandi.background)
        .navigationTitle(String(localized: "settings.ai_tools"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var thresholdSection: some View {
        Section {
            Picker(String(localized: "ai.approval_threshold"), selection: $viewModel.toolApprovalThreshold) {
                Text("ai.always_approve").tag("always")
                Text("ai.moderate_dangerous").tag("moderate")
                Text("ai.dangerous_only").tag("dangerous")
                Text("ai.never_auto_run").tag("never")
            }
            .foregroundStyle(Morandi.primaryText)
            .onChange(of: viewModel.toolApprovalThreshold) { _, _ in viewModel.save() }
        } header: {
            Text("ai.approval")
        } footer: {
            Text("ai.approval_hint")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    private var filterSection: some View {
        Section {
            Picker(localized("common.filter"), selection: $filter) {
                ForEach(Filter.allCases) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var toolsSection: some View {
        ForEach(groupedTools, id: \.category) { group in
            Section(group.category) {
                ForEach(group.tools, id: \.rawName) { entry in
                    toolRow(entry)
                }
            }
        }
    }

    @ViewBuilder
    private func toolRow(_ entry: ToolEntry) -> some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text(entry.displayName)
                        .font(AppTypography.subheadline.weight(.medium))
                        .foregroundStyle(Morandi.primaryText)
                    riskBadge(entry.risk)
                }
                Text(entry.description)
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.secondaryText)
                    .lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { viewModel.enabledToolNames.isEmpty || viewModel.enabledToolNames.contains(entry.rawName) },
                set: { newValue in
                    var set = viewModel.enabledToolNames
                    if set.isEmpty {
                        // Initialize with all tools so toggling off persists correctly.
                        set = Set(registry.allTools.map { type(of: $0).name })
                    }
                    if newValue {
                        set.insert(entry.rawName)
                    } else {
                        set.remove(entry.rawName)
                    }
                    viewModel.enabledToolNames = set
                    viewModel.save()
                }
            ))
            .labelsHidden()
            .tint(Morandi.accent)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func riskBadge(_ risk: ToolRiskLevel) -> some View {
        let color: Color = {
            switch risk {
            case .safe: return Morandi.sage
            case .moderate: return Morandi.clay
            case .dangerous: return Morandi.destructive
            }
        }()
        Text(localizedRiskLabel(for: risk))
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    // MARK: - Data

    private struct ToolEntry {
        let rawName: String
        let displayName: String
        let description: String
        let risk: ToolRiskLevel
        let category: ToolCategory
    }

    private struct ToolGroup {
        let category: String
        let tools: [ToolEntry]
    }

    private var groupedTools: [ToolGroup] {
        let all = registry.allTools.map { tool -> ToolEntry in
            let t = type(of: tool)
            return ToolEntry(
                rawName: t.name,
                displayName: AIToolPresentation.displayName(for: t.name),
                description: AIToolPresentation.displayDescription(for: t.name, fallback: t.description),
                risk: t.riskLevel,
                category: t.category
            )
        }
        let filtered: [ToolEntry]
        switch filter {
        case .all: filtered = all
        case .safe: filtered = all.filter { $0.risk == .safe }
        case .moderate: filtered = all.filter { $0.risk == .moderate }
        case .dangerous: filtered = all.filter { $0.risk == .dangerous }
        }
        let byCategory = Dictionary(grouping: filtered, by: { $0.category })
        return ToolCategory.allCases.compactMap { cat in
            guard let tools = byCategory[cat], !tools.isEmpty else { return nil }
            return ToolGroup(
                category: localizedCategoryName(for: cat),
                tools: tools.sorted { LocalizedSort.isAscending($0.displayName, $1.displayName) }
            )
        }
    }

    private func localizedCategoryName(for category: ToolCategory) -> String {
        switch category {
        case .bookLibrary:
            localized("ai.tool_category.book_library")
        case .bookContent:
            localized("ai.tool_category.book_content")
        case .annotation:
            localized("ai.tool_category.annotation")
        case .search:
            localized("common.search")
        case .readingHistory:
            localized("ai.tool_category.reading_history")
        case .calendar:
            localized("ai.tool_category.calendar")
        case .reminders:
            localized("ai.tool_category.reminders")
        case .utility:
            localized("ai.tool_category.utility")
        case .agent:
            localized("ai.tool_category.agent")
        case .memory:
            localized("ai.memory")
        case .mindmap:
            localized("ai.tool_category.mindmap")
        }
    }

    private func localizedRiskLabel(for risk: ToolRiskLevel) -> String {
        switch risk {
        case .safe:
            localized("ai.tool_filter.safe")
        case .moderate:
            localized("ai.tool_filter.moderate")
        case .dangerous:
            localized("ai.tool_filter.dangerous")
        }
    }
}
