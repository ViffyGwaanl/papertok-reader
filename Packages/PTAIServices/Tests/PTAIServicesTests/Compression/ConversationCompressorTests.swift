import Testing
import Foundation
@testable import PTAIServices

@Suite("ConversationCompressor")
struct ConversationCompressorTests {
    final class RecordingState: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [ChatRequest] = []
        private var _failNext: Bool = false
        private var _summaryText: String = "Earlier: user asked questions; assistant answered."

        func record(_ r: ChatRequest) {
            lock.lock(); defer { lock.unlock() }
            _requests.append(r)
        }
        func setFailNext(_ v: Bool) { lock.lock(); defer { lock.unlock() }; _failNext = v }
        func setSummary(_ s: String) { lock.lock(); defer { lock.unlock() }; _summaryText = s }
        var requests: [ChatRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
        var failNext: Bool { lock.lock(); defer { lock.unlock() }; return _failNext }
        var summaryText: String { lock.lock(); defer { lock.unlock() }; return _summaryText }
    }

    struct StubSummarizer: ChatModelProvider {
        let id: String = "stub-sum"
        let displayName: String = "Stub Summarizer"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]
        let state: RecordingState

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            state.record(request)
            if state.failNext {
                throw ProviderError.serverError(statusCode: 500, message: "boom")
            }
            return ChatResponse(message: .assistant(state.summaryText))
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            state.record(request)
            return AsyncThrowingStream { continuation in
                if state.failNext {
                    continuation.finish(throwing: ProviderError.serverError(statusCode: 500, message: "boom"))
                    return
                }
                continuation.yield(ChatStreamChunk(delta: .text(state.summaryText)))
                continuation.finish()
            }
        }
    }

    private static func makeMessages(_ count: Int) -> [ChatMessage] {
        var out: [ChatMessage] = []
        for i in 0..<count {
            if i.isMultiple(of: 2) {
                out.append(.user("user-\(i)"))
            } else {
                out.append(.assistant("assistant-\(i)"))
            }
        }
        return out
    }

    @Test("passesThroughWhenUnderThreshold")
    func passesThroughWhenUnderThreshold() async throws {
        let state = RecordingState()
        let provider = StubSummarizer(state: state)
        let compressor = ConversationCompressor(
            provider: provider,
            triggerThreshold: 20,
            preserveRecentTurns: 6,
            modelId: "gpt-4o"
        )
        let messages = Self.makeMessages(10)
        let result = try await compressor.compressIfNeeded(messages)
        #expect(result.didCompress == false)
        #expect(result.messages == messages)
        #expect(result.summarizedMessageCount == 0)
        #expect(state.requests.isEmpty)
    }

    @Test("compressesOlderTurnsWhenOverThreshold")
    func compressesOlderTurnsWhenOverThreshold() async throws {
        let state = RecordingState()
        let provider = StubSummarizer(state: state)
        let compressor = ConversationCompressor(
            provider: provider,
            triggerThreshold: 20,
            preserveRecentTurns: 6,
            modelId: "gpt-4o"
        )
        let messages = Self.makeMessages(30)
        let result = try await compressor.compressIfNeeded(messages)
        #expect(result.didCompress == true)
        #expect(result.summarizedMessageCount == 24)
        // 1 system summary + 6 preserved recent = 7
        #expect(result.messages.count == 7)
        #expect(result.messages.first?.role == .system)
    }

    @Test("preservesRecentTurnsExactly")
    func preservesRecentTurnsExactly() async throws {
        let state = RecordingState()
        let provider = StubSummarizer(state: state)
        let compressor = ConversationCompressor(
            provider: provider,
            triggerThreshold: 10,
            preserveRecentTurns: 4,
            modelId: "gpt-4o"
        )
        let messages = Self.makeMessages(15)
        let expectedRecent = Array(messages.suffix(4))
        let result = try await compressor.compressIfNeeded(messages)
        #expect(result.didCompress == true)
        let tail = Array(result.messages.suffix(4))
        #expect(tail == expectedRecent)
    }

    @Test("summaryIsSystemMessage")
    func summaryIsSystemMessage() async throws {
        let state = RecordingState()
        state.setSummary("A concise recap.")
        let provider = StubSummarizer(state: state)
        let compressor = ConversationCompressor(
            provider: provider,
            triggerThreshold: 10,
            preserveRecentTurns: 4,
            modelId: "gpt-4o"
        )
        let messages = Self.makeMessages(15)
        let result = try await compressor.compressIfNeeded(messages)
        let first = result.messages.first
        #expect(first?.role == .system)
        let text = first?.textContent ?? ""
        #expect(text.contains("Earlier conversation summary"))
        #expect(text.contains("A concise recap."))
    }

    @Test("usesInjectedProviderForSummarization")
    func usesInjectedProviderForSummarization() async throws {
        let state = RecordingState()
        let provider = StubSummarizer(state: state)
        let compressor = ConversationCompressor(
            provider: provider,
            triggerThreshold: 10,
            preserveRecentTurns: 4,
            modelId: "gpt-4o-mini"
        )
        _ = try await compressor.compressIfNeeded(Self.makeMessages(15))
        #expect(state.requests.count == 1)
        #expect(state.requests.first?.model == "gpt-4o-mini")
    }

    @Test("failedSummarizationFallsBackToPassthrough")
    func failedSummarizationFallsBackToPassthrough() async throws {
        let state = RecordingState()
        state.setFailNext(true)
        let provider = StubSummarizer(state: state)
        let compressor = ConversationCompressor(
            provider: provider,
            triggerThreshold: 10,
            preserveRecentTurns: 4,
            modelId: "gpt-4o"
        )
        let messages = Self.makeMessages(15)
        let result = try await compressor.compressIfNeeded(messages)
        #expect(result.didCompress == false)
        #expect(result.messages == messages)
    }
}
