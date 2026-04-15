import Testing
import Foundation
@testable import PTFeatures
import PTAIServices
import PTCore

@Suite("AIChatViewModel Streaming Polish (W2.2b)")
struct AIChatViewModelStreamingTests {
    /// Shared mutable state for the stub provider, protected by a lock so the
    /// Sendable provider can expose counters to the test body.
    final class StubState: @unchecked Sendable {
        private let lock = NSLock()
        private var _chunks: [String] = []
        private var _emitDelay: Duration = .zero
        private var _observedCancellation = false

        var chunks: [String] {
            get { lock.lock(); defer { lock.unlock() }; return _chunks }
            set { lock.lock(); _chunks = newValue; lock.unlock() }
        }
        var emitDelay: Duration {
            get { lock.lock(); defer { lock.unlock() }; return _emitDelay }
            set { lock.lock(); _emitDelay = newValue; lock.unlock() }
        }
        var observedCancellation: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _observedCancellation }
            set { lock.lock(); _observedCancellation = newValue; lock.unlock() }
        }
    }

    struct StubStreamingProvider: ChatModelProvider {
        let id: String = "stub-streaming"
        let displayName: String = "Stub Streaming Provider"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]
        let state: StubState

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(message: .assistant("unused"))
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            let state = self.state
            return AsyncThrowingStream { continuation in
                let task = Task {
                    for chunk in state.chunks {
                        if Task.isCancelled {
                            state.observedCancellation = true
                            continuation.finish()
                            return
                        }
                        let delay = state.emitDelay
                        if delay > .zero {
                            try? await Task.sleep(for: delay)
                        }
                        if Task.isCancelled {
                            state.observedCancellation = true
                            continuation.finish()
                            return
                        }
                        continuation.yield(ChatStreamChunk(delta: .text(chunk)))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    private static func makeRuntime(state: StubState) -> AIChatViewModel.Runtime {
        AIChatViewModel.Runtime(
            providers: [
                .init(
                    id: "stub",
                    displayName: "Stub",
                    models: [
                        .init(id: "stub-model", displayName: "Stub Model", supportsThinking: false, supportsVision: false)
                    ],
                    makeProvider: { StubStreamingProvider(state: state) }
                )
            ]
        )
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "AIChatViewModelStreamingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    @Test("streaming debounce coalesces rapid chunks into fewer flushes")
    func streamingDebounceCoalescesUpdates() async {
        let state = StubState()
        state.chunks = Array(repeating: "a", count: 20)
        state.emitDelay = .milliseconds(5)
        let vm = AIChatViewModel(runtime: Self.makeRuntime(state: state), defaults: Self.isolatedDefaults())

        var observedUpdates = 0
        var lastText = ""
        // Poll the observable currentStreamText while the VM streams. A tight
        // polling loop observes every distinct value the debounce flushes.
        let observer = Task { @MainActor in
            while vm.isStreaming || vm.isStreamingTaskActive {
                if vm.currentStreamText != lastText {
                    lastText = vm.currentStreamText
                    observedUpdates += 1
                }
                try? await Task.sleep(for: .milliseconds(2))
            }
        }

        _ = await vm.sendMessage("hi")
        await observer.value

        // 20 chunks at 5ms intervals = ~100ms total. With a 30ms debounce we
        // expect well under 10 distinct flushed values.
        #expect(observedUpdates < 10, "observed \(observedUpdates) flushes; expected < 10")
    }

    @MainActor
    @Test("final chunk flushes immediately on stream finish")
    func streamingFlushesFinalChunkImmediately() async {
        let state = StubState()
        state.chunks = ["hello ", "world", "!"]
        state.emitDelay = .milliseconds(1)
        let vm = AIChatViewModel(runtime: Self.makeRuntime(state: state), defaults: Self.isolatedDefaults())

        _ = await vm.sendMessage("hi")

        // After sendMessage returns the stream is finalized; the assistant
        // message must contain the full concatenation.
        let lastAssistant = vm.messages.last(where: { $0.role == .assistant })?.textContent
        #expect(lastAssistant == "hello world!")
    }

    @MainActor
    @Test("stopStreaming cancels in-flight task and propagates cancellation")
    func stopStreamingCancelsInFlightTask() async {
        let state = StubState()
        state.chunks = Array(repeating: "chunk ", count: 20)
        state.emitDelay = .milliseconds(20)
        let vm = AIChatViewModel(runtime: Self.makeRuntime(state: state), defaults: Self.isolatedDefaults())

        let sendTask = Task { @MainActor in
            _ = await vm.sendMessage("start")
        }
        // Wait long enough that several chunks have been emitted AND the debounce
        // has flushed at least one update into currentStreamText.
        try? await Task.sleep(for: .milliseconds(120))
        vm.stopStreaming()
        await sendTask.value

        #expect(vm.isStreamingTaskActive == false)
        #expect(state.observedCancellation == true)
        let finalized = vm.messages.last(where: { $0.role == .assistant })?.textContent ?? ""
        #expect(finalized.isEmpty == false, "partial content should be preserved as a finalized assistant message")
    }

    @MainActor
    @Test("stopStreaming clears the streaming task handle")
    func stopStreamingClearsTaskHandle() async {
        let state = StubState()
        state.chunks = Array(repeating: "x", count: 10)
        state.emitDelay = .milliseconds(100)
        let vm = AIChatViewModel(runtime: Self.makeRuntime(state: state), defaults: Self.isolatedDefaults())

        let sendTask = Task { @MainActor in
            _ = await vm.sendMessage("start")
        }
        try? await Task.sleep(for: .milliseconds(40))
        vm.stopStreaming()
        await sendTask.value

        #expect(vm.isStreamingTaskActive == false)
        #expect(vm.isStreaming == false)
    }

    @MainActor
    @Test("cancellation does not surface as an error to the UI")
    func cancellationDoesNotSurfaceAsError() async {
        let state = StubState()
        state.chunks = Array(repeating: "y", count: 10)
        state.emitDelay = .milliseconds(100)
        let vm = AIChatViewModel(runtime: Self.makeRuntime(state: state), defaults: Self.isolatedDefaults())

        let sendTask = Task { @MainActor in
            _ = await vm.sendMessage("start")
        }
        try? await Task.sleep(for: .milliseconds(40))
        vm.stopStreaming()
        await sendTask.value

        #expect(vm.errorMessage == nil)
    }
}
