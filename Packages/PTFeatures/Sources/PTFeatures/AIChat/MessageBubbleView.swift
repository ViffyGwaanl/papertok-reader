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
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                if let ts = timestamp {
                    Text(relativeTimeString(ts))
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.tertiaryText)
                        .padding(.trailing, 4)
                }
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    attachmentViews
                    if let text = message.textContent, !text.isEmpty {
                        Text(text)
                            .font(AppTypography.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Morandi.accent)
                            .foregroundStyle(Color(light: .white, dark: Morandi.cardBackground))
                            .clipShape(
                                .rect(cornerRadii: RectangleCornerRadii(
                                    topLeading: 18,
                                    bottomLeading: 18,
                                    bottomTrailing: 4,
                                    topTrailing: 18
                                ))
                            )
                            .textSelection(.enabled)
                            .contextMenu { userMenu(text: text) }
                    }
                }
                statusBadge
            }
            userAvatar
        }
    }

    // MARK: Assistant bubble

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            assistantAvatar
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                if let ts = timestamp {
                    Text(relativeTimeString(ts))
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.tertiaryText)
                        .padding(.leading, 4)
                }
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    if let text = message.textContent, !text.isEmpty {
                        assistantContent(text)
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
            }
            Spacer(minLength: 48)
        }
    }

    @ViewBuilder
    private func assistantContent(_ text: String) -> some View {
        let blocks = MarkdownBlockParser.parse(text)
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(blocks.indices, id: \.self) { i in
                switch blocks[i] {
                case .text(let t):
                    Text(markdownAttributedString(t))
                        .font(AppTypography.body)
                        .foregroundStyle(Morandi.primaryText)
                        .textSelection(.enabled)
                        .tint(Morandi.accent)
                case .codeBlock(let language, let code):
                    CodeBlockView(language: language, code: code)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Morandi.cardBackground)
        .clipShape(
            .rect(cornerRadii: RectangleCornerRadii(
                topLeading: 18,
                bottomLeading: 4,
                bottomTrailing: 18,
                topTrailing: 18
            ))
        )
        .contextMenu { assistantMenu(text: text) }
    }

    // MARK: - Avatars & Status

    private var assistantAvatar: some View {
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
    }

    private var userAvatar: some View {
        Circle()
            .fill(Morandi.stone)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let status {
            HStack(spacing: 4) {
                switch status {
                case .sending:
                    ProgressView().scaleEffect(0.6).tint(Morandi.secondaryText)
                    Text("common.sending").font(AppTypography.caption2).foregroundStyle(Morandi.tertiaryText)
                case .sent:
                    Image(systemName: "checkmark").font(.system(size: 10)).foregroundStyle(Morandi.sage)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 10)).foregroundStyle(Morandi.destructive)
                    Text("intent.result.failed").font(AppTypography.caption2).foregroundStyle(Morandi.destructive)
                    if let onRetry {
                        Button("common.retry", action: onRetry)
                            .font(AppTypography.caption2)
                            .foregroundStyle(Morandi.accent)
                    }
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func relativeTimeString(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, equalTo: Date(), toGranularity: .day) || calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.doesRelativeDateFormatting = true
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .short
        let relative = relativeFormatter.localizedString(for: date, relativeTo: Date())
        if !relative.isEmpty, relative != date.description {
            return relative
        }

        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(.autoupdatingCurrent)
        )
    }

    @ViewBuilder
    private func userMenu(text: String) -> some View {
        messageCopyMenu(text: text)
        if status == .failed, let onRetry {
            Button { onRetry() } label: { Label("common.retry", systemImage: "arrow.clockwise") }
        }
    }

    @ViewBuilder
    private func assistantMenu(text: String) -> some View {
        messageCopyMenu(text: text)
        if let onRegenerate {
            Button { onRegenerate() } label: { Label("ai.regenerate", systemImage: "arrow.clockwise") }
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

    /// Converts markdown text to an AttributedString with full option set.
    private func markdownAttributedString(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return attributed
        }
        return AttributedString(text)
    }
}

// MARK: - Markdown Block Parser

enum MarkdownBlockParser {
    enum Block {
        case text(String)
        case codeBlock(language: String, code: String)
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var currentText = ""
        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("```") {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }
            currentText += line + "\n"
            i += 1
        }
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { blocks.append(.text(trimmed)) }
        return blocks
    }
}
