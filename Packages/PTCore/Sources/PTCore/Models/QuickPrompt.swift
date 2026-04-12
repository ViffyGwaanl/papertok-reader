import Foundation

/// A reusable quick-prompt template for common AI actions on selected text.
public struct QuickPrompt: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var promptText: String
    public var iconName: String
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        title: String,
        promptText: String,
        iconName: String,
        sortOrder: Int
    ) {
        self.id = id
        self.title = title
        self.promptText = promptText
        self.iconName = iconName
        self.sortOrder = sortOrder
    }

    // MARK: - Factory

    /// Common built-in prompts for reader text selection actions.
    public static let explain = QuickPrompt(
        title: "Explain",
        promptText: "Please explain the following passage clearly and concisely:\n\n\"{text}\"",
        iconName: "lightbulb",
        sortOrder: 0
    )

    public static let summarize = QuickPrompt(
        title: "Summarize",
        promptText: "Please summarize the key points of this passage:\n\n\"{text}\"",
        iconName: "text.justify.leading",
        sortOrder: 1
    )

    public static let translate = QuickPrompt(
        title: "Translate",
        promptText: "Please translate the following text into the user's preferred language:\n\n\"{text}\"",
        iconName: "globe",
        sortOrder: 2
    )

    public static let define = QuickPrompt(
        title: "Define",
        promptText: "Please define and explain the vocabulary in this passage:\n\n\"{text}\"",
        iconName: "character.book.closed",
        sortOrder: 3
    )

    /// All built-in prompts sorted by `sortOrder`.
    public static let builtIn: [QuickPrompt] = [explain, summarize, translate, define]
}
