import AppIntents

/// Siri Shortcut: "Ask PaperTok AI [question]"
struct AskAIIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask AI"
    static let description = IntentDescription("Send a message to PaperTok Reader's AI assistant")

    @Parameter(title: "Question")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DeepLinkRouter.shared.route(to: .aiChat(initialMessage: question))
        return .result(dialog: "Sent question: \(question)")
    }
}
