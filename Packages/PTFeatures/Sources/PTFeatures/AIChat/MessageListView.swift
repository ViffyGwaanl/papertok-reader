import SwiftUI
import PTAIServices
import PTUI

/// Scrollable message list that auto-scrolls to bottom during streaming.
///
/// Matches Flutter AiChatStream auto-scroll behavior:
/// - Pins to bottom when streaming starts
/// - Stops auto-scroll if user manually scrolls up
struct MessageListView: View {
    let viewModel: AIChatViewModel
    private let bottomAnchor = "bottom_anchor"

    private struct EditingContext: Identifiable {
        let id: String
        let originalText: String
    }
    @State private var editingContext: EditingContext?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppSpacing.md) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(
                            message: message,
                            timestamp: viewModel.timestamp(for: message.id),
                            status: viewModel.messageStatuses[message.id],
                            onCopy: { _ in },
                            onRegenerate: message.role == .assistant ? {
                                Task { await viewModel.regenerateLastAssistant() }
                            } : nil,
                            onRetry: message.role == .user ? {
                                Task { await viewModel.retryLastUserMessage() }
                            } : nil,
                            onEdit: message.role == .user ? {
                                editingContext = EditingContext(
                                    id: message.id,
                                    originalText: message.textContent ?? ""
                                )
                            } : nil,
                            onRetryMessage: message.role == .assistant ? {
                                let capturedId = message.id
                                Task { await viewModel.retry(messageId: capturedId) }
                            } : nil,
                            branchNavigator: viewModel.branchNavigatorState(for: message.id),
                            onPreviousBranch: {
                                if let sibling = viewModel.siblingNodeId(for: message.id, offset: -1) {
                                    viewModel.switchToBranch(sibling)
                                }
                            },
                            onNextBranch: {
                                if let sibling = viewModel.siblingNodeId(for: message.id, offset: 1) {
                                    viewModel.switchToBranch(sibling)
                                }
                            }
                        )
                        .padding(.horizontal, AppSpacing.lg)
                    }

                    // Typing indicator before first token
                    if viewModel.isStreaming && viewModel.currentStreamText.isEmpty {
                        TypingIndicatorView()
                            .padding(.horizontal, AppSpacing.lg)
                    }

                    // Streaming in-progress bubble
                    if viewModel.isStreaming && !viewModel.currentStreamText.isEmpty {
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        LinearGradient(
                                            colors: [Morandi.accent, Morandi.lavender],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            Text(viewModel.currentStreamText)
                                .font(AppTypography.body)
                                .foregroundStyle(Morandi.primaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Morandi.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .animation(.default, value: viewModel.currentStreamText)
                            Spacer(minLength: 48)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.vertical, AppSpacing.md)
            }
            .background(Morandi.background)
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.currentStreamText) {
                if viewModel.isStreaming { scrollToBottom(proxy: proxy) }
            }
            .sheet(item: $editingContext) { context in
                MessageEditSheet(
                    originalText: context.originalText,
                    onSend: { newText in
                        let messageId = context.id
                        Task { await viewModel.editAndResend(messageId: messageId, newText: newText) }
                    },
                    onCancel: {}
                )
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}
