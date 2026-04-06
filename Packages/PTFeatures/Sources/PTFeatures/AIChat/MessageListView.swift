import SwiftUI
import PTAIServices
import PTUI

/// Scrollable message list that auto-scrolls to bottom during streaming.
///
/// Matches Flutter AiChatStream auto-scroll behavior:
/// - Pins to bottom when streaming starts
/// - Stops auto-scroll if user manually scrolls up
struct MessageListView: View {
    let messages: [ChatMessage]
    let streamingText: String
    let isStreaming: Bool
    private let bottomAnchor = "bottom_anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppSpacing.md) {
                    ForEach(messages) { message in
                        MessageBubbleView(message: message)
                            .padding(.horizontal, AppSpacing.lg)
                    }
                    // Streaming in-progress bubble
                    if isStreaming && !streamingText.isEmpty {
                        HStack {
                            Text(streamingText)
                                .font(AppTypography.body)
                                .foregroundStyle(Morandi.primaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Morandi.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .animation(.default, value: streamingText)
                            Spacer(minLength: 48)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }
                    // Scroll anchor
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.vertical, AppSpacing.md)
            }
            .background(Morandi.background)
            .onChange(of: messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: streamingText) {
                if isStreaming { scrollToBottom(proxy: proxy) }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}
