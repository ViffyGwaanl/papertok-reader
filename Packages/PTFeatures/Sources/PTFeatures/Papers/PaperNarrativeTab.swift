import Foundation

/// Segmented tabs inside the paper detail sheet for switching between the
/// structured explanation (解读) and the dialogue transcript (对话).
public enum PaperNarrativeTab: String, CaseIterable, Hashable, Sendable {
    case explanation
    case dialogue

    public static let defaultTab: PaperNarrativeTab = .explanation

    /// Catalog key that resolves to the localized label shown in the segmented picker.
    public var titleKey: String {
        switch self {
        case .explanation: return "papers.detail.tab.explanation"
        case .dialogue: return "papers.detail.tab.dialogue"
        }
    }
}

/// Native Markdown -> AttributedString parser used by the paper detail narrative.
/// Uses SwiftUI's built-in `AttributedString(markdown:options:)` so no third-party
/// dependency is required. Returns the plain string on parse failure.
public enum PaperMarkdown {
    public static func render(_ markdown: String) -> AttributedString {
        if markdown.isEmpty { return AttributedString("") }
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: markdown, options: options) {
            return parsed
        }
        return AttributedString(markdown)
    }
}
