import Testing
import Foundation
@testable import PTAIServices

@Suite("AutoTitleService")
struct AutoTitleServiceTests {
    final class RecordingState: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [ChatRequest] = []
        private var _response: String = "A Short Four Word Title"
        private var _failNext: Bool = false

        func record(_ r: ChatRequest) { lock.lock(); defer { lock.unlock() }; _requests.append(r) }
        func setResponse(_ s: String) { lock.lock(); defer { lock.unlock() }; _response = s }
        func setFailNext(_ v: Bool) { lock.lock(); defer { lock.unlock() }; _failNext = v }
        var requests: [ChatRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
        var response: String { lock.lock(); defer { lock.unlock() }; return _response }
        var failNext: Bool { lock.lock(); defer { lock.unlock() }; return _failNext }
    }

    struct StubTitleProvider: ChatModelProvider {
        let id: String = "stub-title"
        let displayName: String = "Stub Title"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]
        let state: RecordingState

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            state.record(request)
            if state.failNext {
                throw ProviderError.serverError(statusCode: 500, message: "nope")
            }
            return ChatResponse(message: .assistant(state.response))
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            state.record(request)
            return AsyncThrowingStream { continuation in
                if state.failNext {
                    continuation.finish(throwing: ProviderError.serverError(statusCode: 500, message: "nope"))
                    return
                }
                continuation.yield(ChatStreamChunk(delta: .text(state.response)))
                continuation.finish()
            }
        }
    }

    @Test("returnsNilForShortConversation")
    func returnsNilForShortConversation() async {
        let state = RecordingState()
        let service = AutoTitleService(provider: StubTitleProvider(state: state), modelId: "gpt-4o")
        let result = await service.generateTitle(from: [.user("hello")])
        #expect(result == nil)
        #expect(state.requests.isEmpty)
    }

    @Test("generatesTitleFromTwoTurns")
    func generatesTitleFromTwoTurns() async {
        let state = RecordingState()
        state.setResponse("Exploring Chess Openings Together")
        let service = AutoTitleService(provider: StubTitleProvider(state: state), modelId: "gpt-4o")
        let result = await service.generateTitle(from: [
            .user("Tell me about chess openings"),
            .assistant("Sure, the Sicilian is...")
        ])
        #expect(result == "Exploring Chess Openings Together")
        #expect(state.requests.count == 1)
    }

    @Test("truncatesLongResponses")
    func truncatesLongResponses() async {
        let state = RecordingState()
        let long = String(repeating: "word ", count: 40) // 200 chars
        state.setResponse(long)
        let service = AutoTitleService(provider: StubTitleProvider(state: state), modelId: "gpt-4o")
        let result = await service.generateTitle(from: [
            .user("hi"),
            .assistant("hello")
        ])
        let title = result ?? ""
        #expect(title.count <= 80)
    }

    @Test("localeBiasIncludedInPrompt")
    func localeBiasIncludedInPrompt() async {
        let state = RecordingState()
        let service = AutoTitleService(provider: StubTitleProvider(state: state), modelId: "gpt-4o")
        _ = await service.generateTitle(
            from: [.user("hi"), .assistant("hello")],
            locale: Locale(identifier: "zh-Hans")
        )
        let systemText = state.requests.first?.messages.first?.textContent ?? ""
        #expect(systemText.contains("Chinese") || systemText.contains("中文"))
    }

    @Test("failedGenerationReturnsNil")
    func failedGenerationReturnsNil() async {
        let state = RecordingState()
        state.setFailNext(true)
        let service = AutoTitleService(provider: StubTitleProvider(state: state), modelId: "gpt-4o")
        let result = await service.generateTitle(from: [
            .user("hi"),
            .assistant("hello")
        ])
        #expect(result == nil)
    }
}
