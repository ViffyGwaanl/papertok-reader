import AppIntents

struct SendMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.send_message.title"
    static let description = IntentDescription("intent.send_message.description")
    static let openAppWhenRun = false

    @Parameter(title: "intent.send_message.parameter.message")
    var prompt: String

    @Parameter(title: "intent.send_message.parameter.images")
    var images: [IntentFile]?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let response = try await ShortcutAIService().sendMessage(prompt: prompt, images: images)
        return .result(value: response)
    }
}
