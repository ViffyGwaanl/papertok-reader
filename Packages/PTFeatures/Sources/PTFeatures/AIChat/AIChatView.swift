import SwiftUI
import PTAIServices
import PTCore
import PTUI

/// Main AI chat screen.
///
/// Matches Flutter AiChatStream top-level layout:
/// - NavigationBar with provider name + model picker button
/// - Message list (MessageListView)
/// - Input bar (ChatInputView) pinned to bottom
/// - Tool approval sheet (.sheet on pendingApprovals)
///
/// W5.3: the in-chat provider/model picker has been retired. Tapping the
/// read-only provider chip now posts `openAIProviderSettings`, which the
/// root `ContentView` translates into a jump to Settings → AI Provider Center.
/// Re-resolution of the selected provider happens on every send via
/// `StoredAIProviderCatalog` + the `configurationDidChangeNotification`
/// observed by `AIChatViewModel`.
public struct AIChatView: View {
    private struct SuggestedPrompt: Identifiable {
        let id: String
        let icon: String
        let titleKey: String
        let promptKey: String
    }

    @Bindable var viewModel: AIChatViewModel
    @State private var inputText: String = ""
    @State private var showAttachmentPicker = false
    @State private var showChatSettings = false
    @State private var showConversationList = false
    /// W6.2 — toggles the lightweight in-chat model picker sheet. Short-tap
    /// on the composer model chip opens this; the provider chip to the left
    /// still routes to Settings → AI Provider Center.
    @State private var showModelPicker = false

    private var currentProviderDisplayName: String {
        viewModel.displayedProviderName.isEmpty
            ? String(localized: "common.model")
            : viewModel.displayedProviderName
    }

    private var currentModelDisplayName: String {
        viewModel.displayedModelName
    }

    private var currentModelSupportsThinking: Bool {
        guard let provider = viewModel.providerOptions.first(where: { $0.id == viewModel.selectedProviderId }) else { return false }
        return provider.models.first(where: { $0.id == viewModel.selectedModelId })?.supportsThinking ?? false
    }

    /// W6.2 — the list surfaced in the in-chat model picker. Reads from the
    /// currently-resolved runtime so it always reflects the latest catalog
    /// snapshot (which may include models persisted by the detailed settings
    /// screen).
    private var availableModelsForCurrentProvider: [String] {
        guard let provider = viewModel.providerOptions.first(where: { $0.id == viewModel.selectedProviderId }) else {
            return []
        }
        return provider.models.map(\.id)
    }

    private var quickPrompts: [String] {
        [
            String(localized: "reader.quick_action.explain.title"),
            String(localized: "reader.quick_action.summarize.title"),
            String(localized: "reader.quick_action.translate.title"),
            String(localized: "reader.quick_action.define_vocabulary.title"),
        ]
    }

    private let suggestedPrompts: [SuggestedPrompt] = [
        .init(
            id: "explain",
            icon: "lightbulb",
            titleKey: "reader.quick_action.explain.title",
            promptKey: "reader.quick_action.explain.subtitle"
        ),
        .init(
            id: "summarize",
            icon: "text.quote",
            titleKey: "reader.quick_action.summarize.title",
            promptKey: "reader.quick_action.summarize.subtitle"
        ),
        .init(
            id: "translate",
            icon: "character.bubble",
            titleKey: "reader.quick_action.translate.title",
            promptKey: "reader.quick_action.translate.subtitle"
        ),
        .init(
            id: "define",
            icon: "text.book.closed",
            titleKey: "reader.quick_action.define_vocabulary.title",
            promptKey: "reader.quick_action.define_vocabulary.subtitle"
        ),
    ]

    public init(viewModel: AIChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            if viewModel.messages.count <= 1 && !viewModel.isStreaming {
                emptyState
            } else {
                MessageListView(viewModel: viewModel)
            }

            Divider().background(Morandi.divider)

            ChatInputView(
                text: $inputText,
                isStreaming: viewModel.isStreaming,
                attachments: viewModel.attachments,
                hasMessages: viewModel.messages.count > 1,
                quickPrompts: quickPrompts,
                onSend: handleSend,
                onStop: { viewModel.stopStreaming() },
                onAttach: { showAttachmentPicker = true },
                onRemoveAttachment: { id in viewModel.removeAttachment(id: id) },
                onProviderTap: {
                    // W5.3: provider selection is consolidated in Settings →
                    // AI Provider Center. The chip is a read-only CTA that
                    // requests navigation via a notification observed by
                    // ContentView.
                    NotificationCenter.default.post(
                        name: .openAIProviderSettings,
                        object: nil
                    )
                },
                onModelTap: { showModelPicker = true },
                onModelSettingsTap: { showChatSettings = true },
                onToggleThinking: { viewModel.toggleThinking() },
                onPasteImage: { data in
                    viewModel.addAttachment(
                        .init(type: .image, name: "pasted-image", data: data)
                    )
                    viewModel.infoMessage = String(localized: "chat.input.image_pasted")
                },
                thinkingEnabled: viewModel.thinkingEnabled,
                supportsThinking: currentModelSupportsThinking,
                currentProviderName: currentProviderDisplayName,
                currentModelName: currentModelDisplayName
            )
        }
        .background(Morandi.background)
        .navigationTitle("ai.app_name")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: AppSpacing.md) {
                    if viewModel.persistenceService != nil {
                        Button {
                            showConversationList = true
                        } label: {
                            Image(systemName: "text.bubble")
                                .foregroundStyle(Morandi.accent)
                        }
                        .disabled(viewModel.isStreaming)
                        .accessibilityLabel(Text("ai.conversations"))
                    }

                    Button {
                        viewModel.clearConversation()
                        inputText = ""
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Morandi.accent)
                    }
                    .disabled(viewModel.isStreaming)
                    Button {
                        showChatSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Morandi.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showConversationList) {
            if let persistenceService = viewModel.persistenceService {
                NavigationStack {
                    ConversationListView(
                        viewModel: ConversationListViewModel(
                            persistence: persistenceService,
                            chatViewModel: viewModel
                        ),
                        currentBookId: viewModel.currentBookId,
                        onSelect: { id in
                            if viewModel.isStreaming == false,
                               viewModel.loadConversation(id: id) {
                                showConversationList = false
                            }
                        },
                        onNewChat: {
                            guard viewModel.isStreaming == false else { return }
                            viewModel.clearConversation()
                            inputText = ""
                            showConversationList = false
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showChatSettings) {
            ChatSettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showModelPicker) {
            InChatModelPickerSheet(
                currentProviderId: viewModel.selectedProviderId,
                currentProviderName: currentProviderDisplayName,
                currentModelId: viewModel.selectedModelId,
                availableModels: availableModelsForCurrentProvider,
                onSelect: { modelId in
                    viewModel.setModelForCurrentProvider(modelId)
                },
                onCustomSubmit: { modelId in
                    viewModel.setModelForCurrentProvider(modelId)
                }
            )
        }
        .sheet(item: Binding(
            get: { viewModel.pendingApprovals.first(where: { $0.isApproved == nil }) },
            set: { _ in }
        )) { approval in
            ToolApprovalSheet(
                toolName: approval.toolName,
                arguments: approval.arguments,
                onApprove: { viewModel.resolveApproval(id: approval.id, approved: true) },
                onDeny: { viewModel.resolveApproval(id: approval.id, approved: false) }
            )
        }
    }

    @ViewBuilder
    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(error)
                .font(AppTypography.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer()
            Button("common.retry") {
                Task { await viewModel.retryLastUserMessage() }
            }
            .font(AppTypography.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 4)
            .background(Capsule().stroke(Color.white.opacity(0.5)))
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(Morandi.destructive)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                Spacer(minLength: AppSpacing.xl)
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(
                            LinearGradient(
                                colors: [Morandi.accent, Morandi.lavender],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                    Image(systemName: "sparkles")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(spacing: AppSpacing.xs) {
                    Text("ai.app_name")
                        .font(AppTypography.largeTitle.weight(.bold))
                        .foregroundStyle(Morandi.primaryText)
                    Text("ai.empty.subtitle")
                        .font(AppTypography.body)
                        .foregroundStyle(Morandi.secondaryText)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.md) {
                    ForEach(suggestedPrompts) { p in
                        Button {
                            inputText = String(localized: String.LocalizationValue(p.promptKey))
                            handleSend()
                        } label: {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Image(systemName: p.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Morandi.accent)
                                Text(LocalizedStringKey(p.titleKey))
                                    .font(AppTypography.callout.weight(.semibold))
                                    .foregroundStyle(Morandi.primaryText)
                                    .lineLimit(1)
                                Text(LocalizedStringKey(p.promptKey))
                                    .font(AppTypography.caption2)
                                    .foregroundStyle(Morandi.secondaryText)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppSpacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                                    .fill(Morandi.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                                    .strokeBorder(Morandi.divider, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                Spacer(minLength: AppSpacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Morandi.background)
    }

    private func handleSend() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        Task {
            await viewModel.sendMessage(text)
        }
    }
}
