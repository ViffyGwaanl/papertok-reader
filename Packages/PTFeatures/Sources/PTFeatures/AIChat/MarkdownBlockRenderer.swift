import SwiftUI
import PTUI

/// SwiftUI view that renders one `MarkdownBlock` into visible content.
///
/// Inline formatting within each block (bold, italic, strikethrough,
/// inline code, links, citation markers) is delegated to
/// `MessageBubbleView.assistantAttributedBody(for:)` which uses
/// `AttributedString(markdown:)` as its base and then overlays the citation
/// marker styling from `CitationMarkdownRenderer`.
struct MarkdownBlockRenderer: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .paragraph(let text):
            paragraphView(text: text)
        case .unorderedList(let items):
            ListRenderer(items: items, ordered: false, startIndex: 1)
        case .orderedList(let items, let startIndex):
            ListRenderer(items: items, ordered: true, startIndex: startIndex)
        case .blockquote(let inner):
            BlockquoteRenderer(blocks: inner)
        case .codeBlock(let language, let code):
            CodeBlockView(language: language ?? "", code: code)
        case .horizontalRule:
            Divider()
                .overlay(Morandi.divider)
                .padding(.vertical, AppSpacing.xs)
        case .table(let headers, let rows):
            TableRenderer(headers: headers, rows: rows)
        }
    }

    // MARK: - Heading

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        Text(MessageBubbleView.assistantAttributedBody(for: text))
            .font(headingFont(level: level))
            .fontWeight(.semibold)
            .foregroundStyle(Morandi.primaryText)
            .padding(.top, AppSpacing.sm)
            .textSelection(.enabled)
            .tint(Morandi.accent)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(.title)
        case 2: return .system(.title2)
        case 3: return .system(.title3)
        case 4: return .system(.headline)
        case 5: return .system(.subheadline).weight(.semibold)
        default: return .system(.body).weight(.semibold)
        }
    }

    // MARK: - Paragraph

    @ViewBuilder
    private func paragraphView(text: String) -> some View {
        Text(MessageBubbleView.assistantAttributedBody(for: text))
            .font(AppTypography.body)
            .foregroundStyle(Morandi.primaryText)
            .lineSpacing(4)
            .textSelection(.enabled)
            .tint(Morandi.accent)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - List

private struct ListRenderer: View {
    let items: [MarkdownListItem]
    let ordered: Bool
    let startIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ForEach(items.indices, id: \.self) { idx in
                let item = items[idx]
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Text(marker(for: idx, indent: item.indent))
                        .font(AppTypography.body.monospacedDigit())
                        .foregroundStyle(Morandi.secondaryText)
                    Text(MessageBubbleView.assistantAttributedBody(for: item.text))
                        .font(AppTypography.body)
                        .foregroundStyle(Morandi.primaryText)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .tint(Morandi.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.leading, CGFloat(item.indent) * 16)
            }
        }
    }

    private func marker(for idx: Int, indent: Int) -> String {
        if ordered {
            // Count how many same-indent items preceded this one to compute numbering.
            var n = startIndex
            for j in 0..<idx {
                if items[j].indent == indent { n += 1 }
            }
            return "\(n)."
        } else {
            switch indent {
            case 0: return "•"
            case 1: return "◦"
            default: return "▪"
            }
        }
    }
}

// MARK: - Blockquote

struct BlockquoteRenderer: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Rectangle()
                .fill(Morandi.accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(blocks.indices, id: \.self) { i in
                    MarkdownBlockRenderer(block: blocks[i])
                        .italic()
                }
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}

// MARK: - Table

private struct TableRenderer: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            Grid(alignment: .leading, horizontalSpacing: AppSpacing.md, verticalSpacing: AppSpacing.xs) {
                GridRow {
                    ForEach(headers.indices, id: \.self) { i in
                        Text(MessageBubbleView.assistantAttributedBody(for: headers[i]))
                            .font(AppTypography.body.weight(.semibold))
                            .foregroundStyle(Morandi.primaryText)
                    }
                }
                .padding(.vertical, AppSpacing.xxs)
                .background(Morandi.divider.opacity(0.4))
                ForEach(rows.indices, id: \.self) { r in
                    GridRow {
                        ForEach(rows[r].indices, id: \.self) { c in
                            Text(MessageBubbleView.assistantAttributedBody(for: rows[r][c]))
                                .font(AppTypography.body)
                                .foregroundStyle(Morandi.primaryText)
                        }
                    }
                    .padding(.vertical, AppSpacing.xxs)
                    .background(r.isMultiple(of: 2) ? Color.clear : Morandi.divider.opacity(0.15))
                }
            }
            .padding(AppSpacing.sm)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                    .strokeBorder(Morandi.divider, lineWidth: 0.5)
            )
        } else {
            // Fallback: simple VStack for older platforms.
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(headers.joined(separator: " | "))
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(Morandi.primaryText)
                ForEach(rows.indices, id: \.self) { r in
                    Text(rows[r].joined(separator: " | "))
                        .font(AppTypography.body)
                        .foregroundStyle(Morandi.primaryText)
                }
            }
        }
    }
}
