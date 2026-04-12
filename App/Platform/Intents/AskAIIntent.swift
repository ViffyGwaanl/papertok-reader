import AppIntents

/// Siri Shortcut: "Ask PaperTok AI [question]"
struct AskAIIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.ask_ai.title"
    static let description = IntentDescription("intent.ask_ai.description")
    static let openAppWhenRun = false

    @Parameter(title: "intent.ask_ai.parameter.question")
    var question: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let response = try await ShortcutAIService().sendMessage(prompt: question, images: nil)
        return .result(value: response)
    }
}
