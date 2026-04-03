import Foundation

/// AI-only translation service using the chat provider.
public struct AITranslationService: Sendable {
    private let provider: any ChatModelProvider
    private let model: String

    public init(provider: any ChatModelProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    /// Translate text to the target language.
    public func translate(_ text: String, to targetLanguage: String, from sourceLanguage: String? = nil) async throws -> String {
        let fromClause = sourceLanguage.map { " from \($0)" } ?? ""
        let systemPrompt = "You are a professional translator. Translate the following text\(fromClause) to \(targetLanguage). Output ONLY the translation, nothing else."
        let request = ChatRequest(
            messages: [.system(systemPrompt), .user(text)],
            model: model,
            temperature: 0.3
        )
        let response = try await provider.complete(request)
        return response.message.textContent ?? ""
    }
}
