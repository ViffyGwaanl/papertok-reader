import Foundation

/// LLM-based conversation compressor.
///
/// When `compressIfNeeded` is called with more messages than `triggerThreshold`,
/// the older prefix (everything except the last `preserveRecentTurns` messages) is
/// summarized via a one-shot request to the injected `ChatModelProvider`. The
/// returned message list is `[system summary, ...recent]`. If the provider throws,
/// the original list is returned untouched so the user's send path is not broken.
public actor ConversationCompressor {
    private let provider: ChatModelProvider
    public let triggerThreshold: Int
    public let preserveRecentTurns: Int
    public let modelId: String

    public init(
        provider: ChatModelProvider,
        triggerThreshold: Int = 20,
        preserveRecentTurns: Int = 6,
        modelId: String
    ) {
        self.provider = provider
        self.triggerThreshold = triggerThreshold
        self.preserveRecentTurns = preserveRecentTurns
        self.modelId = modelId
    }

    public struct Result: Sendable {
        public let messages: [ChatMessage]
        public let didCompress: Bool
        public let summarizedMessageCount: Int

        public init(messages: [ChatMessage], didCompress: Bool, summarizedMessageCount: Int) {
            self.messages = messages
            self.didCompress = didCompress
            self.summarizedMessageCount = summarizedMessageCount
        }
    }

    public func compressIfNeeded(_ messages: [ChatMessage]) async throws -> Result {
        guard messages.count > triggerThreshold,
              messages.count > preserveRecentTurns else {
            return Result(messages: messages, didCompress: false, summarizedMessageCount: 0)
        }

        let splitIndex = messages.count - preserveRecentTurns
        let older = Array(messages.prefix(splitIndex))
        let recent = Array(messages.suffix(preserveRecentTurns))

        let request = ChatRequest(
            messages: buildSummarizationMessages(older: older),
            model: modelId,
            temperature: 0.2,
            maxTokens: 1024
        )

        let summary: String
        do {
            summary = try await runSummarization(request)
        } catch {
            return Result(messages: messages, didCompress: false, summarizedMessageCount: 0)
        }

        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return Result(messages: messages, didCompress: false, summarizedMessageCount: 0)
        }

        let summaryMessage = ChatMessage.system("[Earlier conversation summary]\n\n\(trimmed)")
        var compressed: [ChatMessage] = [summaryMessage]
        compressed.append(contentsOf: recent)

        return Result(
            messages: compressed,
            didCompress: true,
            summarizedMessageCount: older.count
        )
    }

    private func runSummarization(_ request: ChatRequest) async throws -> String {
        do {
            let response = try await provider.complete(request)
            return response.message.textContent ?? ""
        } catch {
            return try await collectStreamFallback(request)
        }
    }

    private func collectStreamFallback(_ request: ChatRequest) async throws -> String {
        var collected = ""
        var tokenCount = 0
        let tokenCap = 500
        for try await chunk in provider.stream(request) {
            if case .text(let delta) = chunk.delta {
                collected += delta
                tokenCount += 1
                if tokenCount >= tokenCap { break }
            }
        }
        return collected
    }

    private func buildSummarizationMessages(older: [ChatMessage]) -> [ChatMessage] {
        let instruction = """
        You are summarizing an earlier portion of a chat so the conversation can continue \
        without losing context. Preserve important facts, user intents, decisions, and tool \
        results. Be concise but thorough. Output the summary only, no preamble.
        """
        var transcript = ""
        for message in older {
            let role: String
            switch message.role {
            case .system: role = "System"
            case .user: role = "User"
            case .assistant: role = "Assistant"
            case .tool: role = "Tool"
            }
            let text = message.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty { continue }
            let clipped = text.count > 2000 ? String(text.prefix(2000)) + "... [truncated]" : text
            transcript += "\(role): \(clipped)\n"
        }
        return [
            .system(instruction),
            .user(transcript)
        ]
    }
}
