import SwiftUI
import PTUI

/// SwiftUI wrapper that renders Markdown text with the body typography,
/// delegating parsing to `PaperMarkdown.render(_:)` (which falls back to
/// plain text on parse failure).
struct MarkdownContentView: View {
    let text: String

    var body: some View {
        Text(PaperMarkdown.render(text))
            .font(AppTypography.body)
            .foregroundStyle(Morandi.primaryText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
