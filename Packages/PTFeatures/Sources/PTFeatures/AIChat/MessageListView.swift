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
                            } : nil
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
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}
