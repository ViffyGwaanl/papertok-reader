import SwiftUI
import PTAIServices
import PTUI

/// Main AI chat screen.
///
/// Matches Flutter AiChatStream top-level layout:
/// - NavigationBar with provider name + model picker button
/// - Message list (MessageListView)
/// - Input bar (ChatInputView) pinned to bottom
/// - Tool approval sheet (.sheet on pendingApprovals)
/// - Provider picker sheet (.sheet on showProviderPicker)
public struct AIChatView: View {
    @Bindable var viewModel: AIChatViewModel
    @State private var inputText: String = ""
    @State private var showProviderPicker = false
    @State private var showAttachmentPicker = false

    private let quickPrompts = [
        ChatInputView.QuickPrompt(label: "Explain", prompt: "Please explain this content"),
        ChatInputView.QuickPrompt(label: "Summarize", prompt: "Please summarize the main points"),
        ChatInputView.QuickPrompt(label: "Analyze", prompt: "Please analyze in depth"),
    ]

    public init(viewModel: AIChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Message list
            if viewModel.messages.count <= 1 && !viewModel.isStreaming {
                emptyState
            } else {
                MessageListView(
                    messages: viewModel.messages,
                    streamingText: viewModel.currentStreamText,
                    isStreaming: viewModel.isStreaming
                )
            }

            Divider()
                .background(Morandi.divider)

            // Attachment row
            AttachmentRowView(
                attachments: viewModel.attachments,
                onRemove: { id in viewModel.removeAttachment(id: id) }
            )

            // Input bar
            ChatInputView(
                text: $inputText,
                isStreaming: viewModel.isStreaming,
                quickPrompts: quickPrompts,
                onSend: handleSend,
                onAttach: { showAttachmentPicker = true },
                onStop: { viewModel.isStreaming = false }
            )
        }
        .background(Morandi.background)
        .navigationTitle(viewModel.selectedModelId.isEmpty ? "AI Assistant" : viewModel.selectedModelId)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: AppSpacing.md) {
                    Button {
                        showProviderPicker = true
                    } label: {
                        Image(systemName: "cpu")
                            .foregroundStyle(Morandi.accent)
                    }

                    Button {
                        viewModel.clearConversation()
                        inputText = ""
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Morandi.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showProviderPicker) {
            ProviderPickerSheet(viewModel: viewModel, providers: viewModel.providerOptions)
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

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(Morandi.tertiaryText)
            Text("Start your AI conversation")
                .font(AppTypography.title3)
                .foregroundStyle(Morandi.secondaryText)
            Spacer()
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
