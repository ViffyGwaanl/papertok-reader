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
                    Section(provider.displayName) {
                        ForEach(provider.models) { model in
                            Button {
                                viewModel.selectedProviderId = provider.id
                                viewModel.selectedModelId = model.id
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                        Text(model.displayName)
                                            .font(AppTypography.body)
                                            .foregroundStyle(Morandi.primaryText)
                                        HStack(spacing: AppSpacing.sm) {
                                            if model.supportsThinking {
                                                Label("Thinking", systemImage: "brain")
                                                    .font(AppTypography.caption2)
                                                    .foregroundStyle(Morandi.secondaryText)
                                            }
                                            if model.supportsVision {
                                                Label("Vision", systemImage: "eye")
                                                    .font(AppTypography.caption2)
                                                    .foregroundStyle(Morandi.secondaryText)
                                            }
                                        }
                                    }
                                    Spacer()
                                    if viewModel.selectedProviderId == provider.id
                                        && viewModel.selectedModelId == model.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Morandi.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .background(Morandi.background)
            .navigationTitle("Select Model")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Morandi.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
