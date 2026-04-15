import Testing
import Foundation
@testable import PTFeatures
import PTAIServices
import PTCore

@Suite("AIChatViewModel compression + auto-title wiring (W2.3b)")
struct AIChatViewModelCompressionAutoTitleTests {
    final class RecordingState: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [ChatRequest] = []
        func record(_ r: ChatRequest) { lock.lock(); defer { lock.unlock() }; _requests.append(r) }
        var requests: [ChatRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
    }

    struct StubMainProvider: ChatModelProvider {
        let id: String = "stub-main"
        let displayName: String = "Stub Main"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]
        let state: RecordingState

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            state.record(request)
            return ChatResponse(message: .assistant("ok"))
        }
        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            state.record(request)
            return AsyncThrowingStream { continuation in
                continuation.yield(ChatStreamChunk(delta: .text("assistant reply")))
                continuation.finish()
            }
        }
    }

    struct StubCompressorProvider: ChatModelProvider {
        let id: String = "stub-compressor"
        let displayName: String = "Stub Compressor"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]
        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(message: .assistant("A prior summary."))
        }
        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(ChatStreamChunk(delta: .text("A prior summary.")))
                continuation.finish()
            }
        }
    }

    actor DelayedTitleState {
        var sawGenerate: Bool = false
        func markSeen() { sawGenerate = true }
    }

    struct DelayedTitleProvider: ChatModelProvider {
        let id: String = "stub-title"
        let displayName: String = "Stub Title"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]
        let delayNanos: UInt64
        let state: DelayedTitleState

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            await state.markSeen()
            try? await Task.sleep(nanoseconds: delayNanos)
            return ChatResponse(message: .assistant("Generated Four Word Title"))
        }
        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            AsyncThrowingStream { continuation in
                Task {
                    await state.markSeen()
                    try? await Task.sleep(nanoseconds: delayNanos)
                    continuation.yield(ChatStreamChunk(delta: .text("Generated Four Word Title")))
                    continuation.finish()
                }
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
                    makeProvider: { StubMainProvider(state: state) }
                )
            ]
        )
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "AIChatViewModelCompressionAutoTitleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func makeTempPersistence() -> (ConversationPersistenceService, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("W23bCompAutoTitle-\(UUID().uuidString)")
        let service = ConversationPersistenceService(directory: dir)
        return (service, dir)
    }

    @MainActor
    @Test("compressorRunsBeforeBudgeterInSendPath")
    func compressorRunsBeforeBudgeterInSendPath() async {
        let state = RecordingState()
        let defaults = Self.isolatedDefaults()
        defaults.set("0", forKey: "ai_max_tokens_stub")
        let compressor = ConversationCompressor(
            provider: StubCompressorProvider(),
            triggerThreshold: 3,
            preserveRecentTurns: 2,
            modelId: "gpt-4o"
        )
        let vm = AIChatViewModel(
            runtime: Self.makeRuntime(state: state),
            defaults: defaults,
            compressor: compressor
        )
        // Seed the tree with 6 prior exchanges so the compressor triggers before
        // the new user message is even appended.
        for i in 0..<6 {
            vm.conversationTree.append(i.isMultiple(of: 2) ? .user("u\(i)") : .assistant("a\(i)"))
        }

        _ = await vm.sendMessage("latest")

        let firstRequest = state.requests.first
        #expect(firstRequest != nil)
        let messages = firstRequest?.messages ?? []
        // After compression, first non-system is the summary system, and
        // recent tail is preserved. Expect at least one message whose text
        // contains the summary marker.
        let hasSummary = messages.contains { msg in
            msg.role == .system && (msg.textContent?.contains("Earlier conversation summary") ?? false)
        }
        #expect(hasSummary)
        // The last user message ("latest") must still be present exactly.
        let lastUser = messages.last(where: { $0.role == .user })
        #expect(lastUser?.textContent == "latest")
    }

    @MainActor
    @Test("autoTitleSpawnsAfterFirstAssistantTurn")
    func autoTitleSpawnsAfterFirstAssistantTurn() async {
        let state = RecordingState()
        let defaults = Self.isolatedDefaults()
        defaults.set("0", forKey: "ai_max_tokens_stub")
        let (persistence, tempDir) = Self.makeTempPersistence()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let titleState = DelayedTitleState()
        let titleService = AutoTitleService(
            provider: DelayedTitleProvider(delayNanos: 0, state: titleState),
            modelId: "gpt-4o"
        )
        let vm = AIChatViewModel(
            runtime: Self.makeRuntime(state: state),
            persistenceService: persistence,
            defaults: defaults,
            titleService: titleService
        )

        _ = await vm.sendMessage("first question")

        // Poll briefly for the background task to complete.
        var updatedTitle: String? = nil
        for _ in 0..<50 {
            if let id = vm.conversationId,
               let loaded = try? persistence.load(id: id),
               loaded.title != "" && loaded.title != "New Conversation"
                   && loaded.title.contains("Generated") {
                updatedTitle = loaded.title
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(updatedTitle == "Generated Four Word Title")
        let seen = await titleState.sawGenerate
        #expect(seen == true)
    }

    @MainActor
    @Test("autoTitleDoesNotBlockUserFlow")
    func autoTitleDoesNotBlockUserFlow() async {
        let state = RecordingState()
        let defaults = Self.isolatedDefaults()
        defaults.set("0", forKey: "ai_max_tokens_stub")
        let (persistence, tempDir) = Self.makeTempPersistence()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let titleState = DelayedTitleState()
        let titleService = AutoTitleService(
            provider: DelayedTitleProvider(delayNanos: 100_000_000, state: titleState),
            modelId: "gpt-4o"
        )
        let vm = AIChatViewModel(
            runtime: Self.makeRuntime(state: state),
            persistenceService: persistence,
            defaults: defaults,
            titleService: titleService
        )

        let clock = ContinuousClock()
        let start = clock.now
        _ = await vm.sendMessage("hi")
        let elapsed = clock.now - start
        // sendMessage must return well before the title provider's 100ms delay.
        #expect(elapsed < .milliseconds(90))
    }

    @MainActor
    @Test("autoTitleSkippedForExistingConversation")
    func autoTitleSkippedForExistingConversation() async {
        let state = RecordingState()
        let defaults = Self.isolatedDefaults()
        defaults.set("0", forKey: "ai_max_tokens_stub")
        let (persistence, tempDir) = Self.makeTempPersistence()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let titleState = DelayedTitleState()
        let titleService = AutoTitleService(
            provider: DelayedTitleProvider(delayNanos: 0, state: titleState),
            modelId: "gpt-4o"
        )
        let vm = AIChatViewModel(
            runtime: Self.makeRuntime(state: state),
            persistenceService: persistence,
            defaults: defaults,
            titleService: titleService
        )
        vm.conversationId = "existing-conv"
        vm.conversationTitle = "Already Named"
        // Pre-seed so it looks like there are prior messages.
        vm.conversationTree.append(.user("prior"))
        vm.conversationTree.append(.assistant("prior reply"))

        _ = await vm.sendMessage("follow up")

        // Give the background task a chance — but it should never fire.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let seen = await titleState.sawGenerate
        #expect(seen == false)
    }
}
