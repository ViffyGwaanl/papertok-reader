import SwiftUI
import PTAIServices
import PTUI

/// Bottom sheet for selecting LLM provider and model.
///
/// Matches Flutter AiChatStream's provider selector dropdown behavior.
/// Providers loaded from AIChatViewModel.selectedProviderId.
struct ProviderPickerSheet: View {
    @Bindable var viewModel: AIChatViewModel
    @Environment(\.dismiss) private var dismiss

    let providers: [AIChatViewModel.ProviderOption]

    var body: some View {
        NavigationStack {
            List {
                ForEach(providers) { provider in
                    Section {
                        ForEach(provider.models) { model in
                            modelRow(provider: provider, model: model)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Image(systemName: providerIcon(provider.id))
                                .foregroundStyle(Morandi.accent)
                            Text(provider.displayName)
                                .font(AppTypography.headline)
                                .foregroundStyle(Morandi.primaryText)
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.plain)
            #endif
            .background(Morandi.background)
            .navigationTitle(String(localized: "common.select_model"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                        .foregroundStyle(Morandi.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func modelRow(provider: AIChatViewModel.ProviderOption, model: AIChatViewModel.ModelOption) -> some View {
        let isSelected = viewModel.selectedProviderId == provider.id && viewModel.selectedModelId == model.id
        Button {
            viewModel.selectedProviderId = provider.id
            viewModel.selectedModelId = model.id
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(AppTypography.body.weight(.semibold))
                            .foregroundStyle(Morandi.primaryText)
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { i in
                                Image(systemName: i < costLevel(for: model.id) ? "dollarsign.circle.fill" : "dollarsign.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Morandi.clay)
                            }
                        }
                        Image(systemName: speedIcon(for: model.id))
                            .font(.system(size: 11))
                            .foregroundStyle(Morandi.powder)
                    }
                    Text(description(for: model.id))
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.secondaryText)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        capabilityPill("Streaming", color: Morandi.powder)
                        capabilityPill("Tools", color: Morandi.moss)
                        if model.supportsVision {
                            capabilityPill("Vision", color: Morandi.lavender)
                        }
                        if model.supportsThinking {
                            capabilityPill("Thinking", color: Morandi.dustyRose)
                        }
                    }
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Morandi.accent)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func capabilityPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func providerIcon(_ id: String) -> String {
        switch id.lowercased() {
        case "openai": return "brain.head.profile"
        case "anthropic": return "sparkles"
        case "google", "gemini": return "g.circle"
        case "mistral": return "wind"
        default: return "cpu"
        }
    }

    private func costLevel(for modelId: String) -> Int {
        let m = modelId.lowercased()
        if m.contains("mini") || m.contains("haiku") || m.contains("small") { return 1 }
        if m.contains("sonnet") || m.contains("4.1") { return 2 }
        if m.contains("opus") || m.contains("gpt-4") { return 3 }
        return 2
    }

    private func speedIcon(for modelId: String) -> String {
        let m = modelId.lowercased()
        if m.contains("mini") || m.contains("haiku") || m.contains("small") { return "hare.fill" }
        if m.contains("opus") { return "tortoise.fill" }
        return "figure.walk"
    }

    private func description(for modelId: String) -> String {
        let m = modelId.lowercased()
        if m.contains("mini") { return "Fast, cost-efficient everyday model." }
        if m.contains("haiku") { return "Claude's fastest model for quick tasks." }
        if m.contains("sonnet") { return "Balanced intelligence and speed." }
        if m.contains("opus") { return "Most capable, best for complex reasoning." }
        if m.contains("gpt-4.1") { return "OpenAI's flagship reasoning model." }
        if m.contains("gpt-4o") { return "Multimodal with strong vision skills." }
        return "General-purpose chat model."
    }
}
