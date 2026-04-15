import Foundation

/// One-shot title generation service.
///
/// Given the first user + first assistant turn of a conversation, asks the
/// injected `ChatModelProvider` for a short title (4-8 words) in the locale's
/// language. Returns `nil` on any error or if the conversation is too short,
/// so the save path can fall back to the heuristic title.
public actor AutoTitleService {
    private let provider: ChatModelProvider
    public let modelId: String

    public init(provider: ChatModelProvider, modelId: String) {
        self.provider = provider
        self.modelId = modelId
    }

    public func generateTitle(
        from messages: [ChatMessage],
        locale: Locale = .current
    ) async -> String? {
        guard messages.count >= 2 else { return nil }
        guard let firstUser = messages.first(where: { $0.role == .user })?.textContent,
              firstUser.isEmpty == false else { return nil }
        guard let firstAssistant = messages.first(where: { $0.role == .assistant })?.textContent,
              firstAssistant.isEmpty == false else { return nil }

        let language = preferredLanguageLabel(for: locale)
        let instruction = "Generate ONLY a 4-8 word title, no quotes, no trailing punctuation, in \(language)."
        let context = """
        User: \(clip(firstUser, limit: 600))
        Assistant: \(clip(firstAssistant, limit: 600))
        """

        let request = ChatRequest(
            messages: [.system(instruction), .user(context)],
            model: modelId,
            temperature: 0.4,
            maxTokens: 64
        )

        let raw: String
        do {
            raw = try await runCompletion(request)
        } catch {
            return nil
        }

        let sanitized = sanitize(raw)
        return sanitized.isEmpty ? nil : sanitized
    }

    private func runCompletion(_ request: ChatRequest) async throws -> String {
        do {
            let response = try await provider.complete(request)
            return response.message.textContent ?? ""
        } catch {
            var collected = ""
            for try await chunk in provider.stream(request) {
                if case .text(let delta) = chunk.delta {
                    collected += delta
                    if collected.count >= 400 { break }
                }
            }
            return collected
        }
    }

    private func preferredLanguageLabel(for locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier ?? "en"
        return locale.localizedString(forLanguageCode: code) ?? "English"
    }

    private func clip(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "..."
    }

    private func sanitize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = text.split(separator: "\n").first {
            text = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let quoteChars: Set<Character> = ["\"", "'", "\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}"]
        while let first = text.first, quoteChars.contains(first) {
            text.removeFirst()
        }
        while let last = text.last, quoteChars.contains(last) {
            text.removeLast()
        }
        let trailingPunct: Set<Character> = [".", ",", "!", "?", ";", ":", "\u{3002}", "\u{FF01}", "\u{FF1F}", "\u{FF0C}", "\u{3001}", "\u{FF1B}", "\u{FF1A}"]
        while let last = text.last, trailingPunct.contains(last) {
            text.removeLast()
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count <= 80 { return text }

        let windowEnd = text.index(text.startIndex, offsetBy: 80)
        let window = text[text.startIndex..<windowEnd]
        var lastWhitespace: String.Index? = nil
        var i = window.startIndex
        while i < window.endIndex {
            if window[i].isWhitespace { lastWhitespace = i }
            i = window.index(after: i)
        }
        if let lastWhitespace {
            return String(text[text.startIndex..<lastWhitespace])
        }
        return String(window)
    }
}
