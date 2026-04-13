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
    @State private var showChatSettings = false

    private let quickPrompts = [
        ChatInputView.QuickPrompt(label: "Explain", prompt: "Please explain this content"),
        ChatInputView.QuickPrompt(label: "Summarize", prompt: "Please summarize the main points"),
        ChatInputView.QuickPrompt(label: "Analyze", prompt: "Please analyze in depth"),
    ]

    private let suggestedPrompts: [(icon: String, title: String, prompt: String)] = [
        ("lightbulb", "Explain a concept", "Explain the core idea in simple terms."),
        ("text.quote", "Summarize this page", "Summarize the key points of this page."),
        ("questionmark.circle", "Ask a question", "What questions should I ask about this?"),
        ("sparkles", "Find insights", "What are the most insightful takeaways?"),
        ("list.bullet", "Extract key points", "List the key points as bullet items."),
        ("character.bubble", "Translate", "Translate the main points to my preferred language."),
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

            AttachmentRowView(
                attachments: viewModel.attachments,
                onRemove: { id in viewModel.removeAttachment(id: id) }
            )

            ChatInputView(
                text: $inputText,
                isStreaming: viewModel.isStreaming,
                hasMessages: viewModel.messages.count > 1,
                quickPrompts: quickPrompts,
                onSend: handleSend,
                onAttach: { showAttachmentPicker = true },
                onStop: { viewModel.stopStreaming() }
            )
        }
        .background(Morandi.background)
        .navigationTitle("PaperTok AI")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showProviderPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                        Text(viewModel.selectedModelId.isEmpty ? "Select model" : viewModel.selectedModelId)
                            .font(AppTypography.caption.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Morandi.accent)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Morandi.accent.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: AppSpacing.md) {
                    Button {
                        viewModel.clearConversation()
                        inputText = ""
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Morandi.accent)
                    }
                    Button {
                        showChatSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Morandi.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showProviderPicker) {
            ProviderPickerSheet(viewModel: viewModel, providers: viewModel.providerOptions)
        }
        .sheet(isPresented: $showChatSettings) {
            ChatSettingsSheet(viewModel: viewModel)
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
            Button("Retry") {
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
                    Text("PaperTok AI")
                        .font(AppTypography.largeTitle.weight(.bold))
                        .foregroundStyle(Morandi.primaryText)
                    Text("Your premium reading assistant")
                        .font(AppTypography.body)
                        .foregroundStyle(Morandi.secondaryText)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.md) {
                    ForEach(suggestedPrompts.indices, id: \.self) { i in
                        let p = suggestedPrompts[i]
                        Button {
                            inputText = p.prompt
                            handleSend()
                        } label: {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Image(systemName: p.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Morandi.accent)
                                Text(p.title)
                                    .font(AppTypography.callout.weight(.semibold))
                                    .foregroundStyle(Morandi.primaryText)
                                    .lineLimit(1)
                                Text(p.prompt)
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
