import Testing
import Foundation
@testable import PTFeatures
import PTAIServices
import PTCore

@Suite("AIChatViewModel budget wiring (W2.3a)")
struct AIChatViewModelBudgetTests {
    final class RecordingState: @unchecked Sendable {
        private let lock = NSLock()
        private var _receivedRequests: [ChatRequest] = []

        func record(_ r: ChatRequest) {
            lock.lock(); _receivedRequests.append(r); lock.unlock()
        }
        var receivedRequests: [ChatRequest] {
            lock.lock(); defer { lock.unlock() }; return _receivedRequests
        }
    }

    struct RecordingProvider: ChatModelProvider {
        let id: String = "stub-budget"
        let displayName: String = "Stub Budget"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]
        let state: RecordingState

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            state.record(request)
            return ChatResponse(message: .assistant("ok"))
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            state.record(request)
            return AsyncThrowingStream { continuation in
                continuation.yield(ChatStreamChunk(delta: .text("ok")))
                continuation.finish()
            }
        }
    }

    private static func makeRuntime(state: RecordingState, modelId: String = "gpt-4o") -> AIChatViewModel.Runtime {
        AIChatViewModel.Runtime(
            providers: [
                .init(
                    id: "stub",
                    displayName: "Stub",
                    models: [
                        .init(id: modelId, displayName: modelId, supportsThinking: false, supportsVision: false)
                    ],
                    makeProvider: { RecordingProvider(state: state) }
                )
            ]
        )
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "AIChatViewModelBudgetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    @Test("budgeter runs before provider call: oversized message is clipped before the request is built")
    func budgeterRunsBeforeProviderCall() async {
        let state = RecordingState()
        let defaults = Self.isolatedDefaults()
        // Force user-override off so strategy controls maxTokens formulaically.
        defaults.set("0", forKey: "ai_max_tokens_stub")
        let budgeter = PromptBudgeter(maxCharactersPerMessage: 100, truncationMarker: "[X]")
        let vm = AIChatViewModel(
            runtime: Self.makeRuntime(state: state),
            defaults: defaults,
            promptBudgeter: budgeter
        )

        let huge = String(repeating: "a", count: 500)
        _ = await vm.sendMessage(huge)

        let requests = state.receivedRequests
        #expect(requests.count >= 1)
        let userMsg = requests.first?.messages.last(where: { $0.role == .user })
        let text = userMsg?.textContent ?? ""
        #expect(text.count <= 100 + "[X]".count)
        #expect(text.hasSuffix("[X]"))
        #expect(vm.infoMessage != nil)
    }

    @MainActor
    @Test("maxTokens strategy computes value for request when no user override")
    func maxTokensStrategyComputesValueForRequest() async {
        let state = RecordingState()
        let defaults = Self.isolatedDefaults()
        defaults.set("0", forKey: "ai_max_tokens_stub")
        let vm = AIChatViewModel(
            runtime: Self.makeRuntime(state: state, modelId: "gpt-4o"),
            defaults: defaults,
            maxTokensStrategy: MaxTokensStrategy(safetyMargin: 256)
        )

        _ = await vm.sendMessage("hi")

        let req = state.receivedRequests.first
        // gpt-4o max output is 16_384; small prompt, no user override,
        // so the resolved max_tokens should be clamped to modelMaxOutput.
        #expect(req?.maxTokens == 16_384)
    }

    @MainActor
    @Test("user override maxTokens is respected")
    func userOverrideMaxTokensIsRespected() async {
        let state = RecordingState()
        let defaults = Self.isolatedDefaults()
        defaults.set("1500", forKey: "ai_max_tokens_stub")
        let vm = AIChatViewModel(
            runtime: Self.makeRuntime(state: state, modelId: "gpt-4o"),
            defaults: defaults
        )

        _ = await vm.sendMessage("hi")

        let req = state.receivedRequests.first
        #expect(req?.maxTokens == 1_500)
    }
}
