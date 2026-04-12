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

    public enum Filter: String, CaseIterable, Identifiable {
        case all, safe, moderate, dangerous
        public var id: String { rawValue }
        public var displayName: String { rawValue.capitalized }
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
        .navigationTitle("AI Tools")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var thresholdSection: some View {
        Section {
            Picker("Approval Threshold", selection: $viewModel.toolApprovalThreshold) {
                Text("Always Approve").tag("always")
                Text("Moderate & Dangerous").tag("moderate")
                Text("Dangerous Only").tag("dangerous")
                Text("Never (auto-run)").tag("never")
            }
            .foregroundStyle(Morandi.primaryText)
            .onChange(of: viewModel.toolApprovalThreshold) { _, _ in viewModel.save() }
        } header: {
            Text("Approval")
        } footer: {
            Text("Controls which tools require explicit user approval before being executed by the AI.")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    private var filterSection: some View {
        Section {
            Picker("Filter", selection: $filter) {
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
                ForEach(group.tools, id: \.name) { entry in
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
                    Text(entry.name)
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
                get: { viewModel.enabledToolNames.isEmpty || viewModel.enabledToolNames.contains(entry.name) },
                set: { newValue in
                    var set = viewModel.enabledToolNames
                    if set.isEmpty {
                        // Initialize with all tools so toggling off persists correctly.
                        set = Set(registry.allTools.map { type(of: $0).name })
                    }
                    if newValue {
                        set.insert(entry.name)
                    } else {
                        set.remove(entry.name)
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
        Text(risk.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    // MARK: - Data

    private struct ToolEntry {
        let name: String
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
            return ToolEntry(name: t.name, description: t.description, risk: t.riskLevel, category: t.category)
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
                category: cat.rawValue.capitalized,
                tools: tools.sorted { $0.name < $1.name }
            )
        }
    }
}
