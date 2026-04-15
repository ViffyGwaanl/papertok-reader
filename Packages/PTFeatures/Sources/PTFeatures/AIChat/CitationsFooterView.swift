import SwiftUI
import PTAIServices
import PTUI

/// Renders a "Sources" footer beneath an assistant chat message, listing the
/// message's `[MessageCitation]` entries with index marker, title (optional link),
/// and an optional snippet.
public struct CitationsFooterView: View {
    private let citations: [MessageCitation]

    public init(citations: [MessageCitation]) {
        self.citations = citations
    }

    public var body: some View {
        if citations.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(String(localized: "chat.message.citations.section_title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Morandi.secondaryText)
                ForEach(citations) { citation in
                    citationRow(citation)
                }
            }
            .padding(.top, AppSpacing.sm)
        }
    }

    @ViewBuilder
    private func citationRow(_ citation: MessageCitation) -> some View {
        if let url = citation.url {
            Link(destination: url) {
                rowContent(citation)
            }
            .buttonStyle(.plain)
        } else {
            rowContent(citation)
        }
    }

    @ViewBuilder
    private func rowContent(_ citation: MessageCitation) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text("[\(citation.index)]")
                    .font(.caption.monospaced())
                    .foregroundStyle(Morandi.accent)
                Text(Self.displayTitle(for: citation))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Morandi.primaryText)
                    .lineLimit(2)
            }
            if let snippet = citation.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption2.italic())
                    .foregroundStyle(Morandi.secondaryText)
                    .lineLimit(2)
                    .padding(.leading, AppSpacing.md)
            }
        }
    }

    // MARK: - Test hooks

    static func shouldRender(_ citations: [MessageCitation]) -> Bool {
        !citations.isEmpty
    }

    static func rowCount(for citations: [MessageCitation]) -> Int {
        citations.count
    }

    static func displayTitle(for citation: MessageCitation) -> String {
        let trimmed = citation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "chat.message.citations.untitled")
        }
        return trimmed
    }
}
