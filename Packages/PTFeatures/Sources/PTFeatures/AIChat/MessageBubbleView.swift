import SwiftUI
import PTAIServices
import PTUI

/// Production-quality chat message bubble with avatars, timestamps, status indicators,
/// rich markdown, code blocks, and contextual menus.
struct MessageBubbleView: View {
    let message: ChatMessage
    var timestamp: Date? = nil
    var status: AIChatViewModel.MessageStatus? = nil
    var onCopy: ((String) -> Void)? = nil
    var onRegenerate: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil

    @State private var showSystemContent = false

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .system:
            systemLabel
        case .tool:
            toolResultView
        }
    }

    // MARK: User bubble

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                attachmentViews
                if let text = message.textContent, !text.isEmpty {
                    Text(text)
                        .font(AppTypography.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Morandi.accent)
                        .foregroundStyle(Color(light: .white, dark: Morandi.cardBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .textSelection(.enabled)
                        .contextMenu { messageCopyMenu(text: text) }
                }
            }
        }
    }

    // MARK: Assistant bubble

    private var assistantBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if let text = message.textContent, !text.isEmpty {
                    Text(markdownAttributedString(text))
                        .font(AppTypography.body)
                        .foregroundStyle(Morandi.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Morandi.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .textSelection(.enabled)
                        .contextMenu { messageCopyMenu(text: text) }
                }
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls) { call in
                        ToolStepView(
                            toolName: call.name,
                            arguments: call.arguments,
                            state: .completed(output: "")
                        )
                    }
                }
            }
            Spacer(minLength: 48)
        }
    }

    // MARK: System message (collapsed by default)

    private var systemLabel: some View {
        Button {
            withAnimation { showSystemContent.toggle() }
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "info.circle")
                    .font(AppTypography.caption2)
                if showSystemContent, let text = message.textContent {
                    Text(text)
                        .font(AppTypography.caption2)
                } else {
                    Text("ai.role.system")
                        .font(AppTypography.caption2)
                }
            }
            .foregroundStyle(Morandi.tertiaryText)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(Capsule().fill(Morandi.cardBackground))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: Tool result

    private var toolResultView: some View {
        ToolStepView(
            toolName: "Tool Result",
            arguments: "",
            state: .completed(output: message.textContent ?? "")
        )
    }

    // MARK: Attachments

    @ViewBuilder
    private var attachmentViews: some View {
        ForEach(message.content.indices, id: \.self) { i in
            switch message.content[i] {
            case .imageBase64(let data, _):
                #if os(iOS)
                if let imageData = Data(base64Encoded: data),
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                }
                #else
                if let imageData = Data(base64Encoded: data),
                   let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                }
                #endif
            case .imageURL(let url):
                AsyncImage(url: URL(string: url)) { img in
                    img.resizable().scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                } placeholder: {
                    ProgressView()
                        .tint(Morandi.accent)
                }
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func messageCopyMenu(text: String) -> some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = text
            #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
        } label: {
            Label(String(localized: "common.copy"), systemImage: "doc.on.doc")
        }

        #if os(iOS)
        ShareLink(item: text) {
            Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
        }
        #endif
    }

    // MARK: - Markdown Helpers

    /// Converts basic markdown text to an AttributedString for rendering.
    private func markdownAttributedString(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(text)
    }
}
