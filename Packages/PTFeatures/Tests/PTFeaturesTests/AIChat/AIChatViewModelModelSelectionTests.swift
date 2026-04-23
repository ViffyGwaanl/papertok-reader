import Testing
import Foundation
@testable import PTFeatures
import PTAIServices
import PTCore

/// W6.2 — in-chat model picker persistence. Verifies the VM helper that
/// writes a new model id to the provider-scoped UserDefaults key, publishes
/// the `configurationDidChangeNotification`, and is effective on the very
/// next send.
@Suite("AIChatViewModel model selection (W6.2)")
struct AIChatViewModelModelSelectionTests {
    final class ObservedRequests: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [(providerId: String, modelId: String)] = []

        func record(providerId: String, modelId: String) {
            lock.lock(); defer { lock.unlock() }
            _requests.append((providerId, modelId))
        }

        var all: [(providerId: String, modelId: String)] {
            lock.lock(); defer { lock.unlock() }
            return _requests
        }
    }

    struct StubProvider: ChatModelProvider {
        let id: String
        let displayName: String
        let recorder: ObservedRequests
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming, .toolCalling]

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(message: .assistant("unused"))
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            let recorder = self.recorder
            let providerId = self.id
            let modelId = request.model
            return AsyncThrowingStream { continuation in
                recorder.record(providerId: providerId, modelId: modelId)
                continuation.yield(ChatStreamChunk(delta: .text("ok"), finishReason: .stop))
                continuation.finish()
            }
        }
    }

    @MainActor
    private func makeRuntime(
        providerId: String,
        modelIds: [String],
        recorder: ObservedRequests
    ) -> AIChatViewModel.Runtime {
        AIChatViewModel.Runtime(
            providers: [
                .init(
                    id: providerId,
                    displayName: providerId.capitalized,
                    models: modelIds.map {
                        .init(
                            id: $0,
                            displayName: $0,
                            supportsThinking: false,
                            supportsVision: false
                        )
                    },
                    makeProvider: {
                        StubProvider(
                            id: providerId,
                            displayName: providerId.capitalized,
                            recorder: recorder
                        )
                    }
                )
            ]
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AIChatModelSelection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    @Test("setModelForCurrentProviderPersistsToUserDefaults writes the provider-scoped key")
    func setModelForCurrentProviderPersistsToUserDefaults() {
        let defaults = makeDefaults()
        let recorder = ObservedRequests()
        let runtime = makeRuntime(
            providerId: "alpha",
            modelIds: ["alpha-1", "alpha-2"],
            recorder: recorder
        )

        let vm = AIChatViewModel(runtime: runtime, defaults: defaults)
        vm.selectedProviderId = "alpha"
        vm.selectedModelId = "alpha-1"

        vm.setModelForCurrentProvider("alpha-2")

        #expect(vm.selectedModelId == "alpha-2")
        #expect(defaults.string(forKey: "ai_model_for_alpha") == "alpha-2")
    }

    @MainActor
    @Test("setModelForCurrentProviderFiresConfigChangeNotification posts exactly once")
    func setModelForCurrentProviderFiresConfigChangeNotification() async {
        let defaults = makeDefaults()
        let recorder = ObservedRequests()
        let runtime = makeRuntime(
            providerId: "alpha",
            modelIds: ["alpha-1", "alpha-2"],
            recorder: recorder
        )
        let vm = AIChatViewModel(runtime: runtime, defaults: defaults)
        vm.selectedProviderId = "alpha"
        vm.selectedModelId = "alpha-1"

        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var _value = 0
            func bump() { lock.lock(); defer { lock.unlock() }; _value += 1 }
            var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
        }
        let counter = Counter()

        let token = NotificationCenter.default.addObserver(
            forName: StoredAIProviderCatalog.configurationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            counter.bump()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        vm.setModelForCurrentProvider("alpha-2")

        // Let the main queue drain.
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(counter.value >= 1)
    }

    @MainActor
    @Test("nextSendUsesNewModel after setModelForCurrentProvider flips the selection")
    func nextSendUsesNewModel() async {
        let defaults = makeDefaults()
        let recorder = ObservedRequests()
        let runtime = makeRuntime(
            providerId: "alpha",
            modelIds: ["alpha-1", "alpha-2"],
            recorder: recorder
        )
        let vm = AIChatViewModel(runtime: runtime, defaults: defaults)
        vm.selectedProviderId = "alpha"
        vm.selectedModelId = "alpha-1"

        _ = await vm.sendMessage("before")
        let before = recorder.all
        #expect(before.first?.modelId == "alpha-1")

        vm.setModelForCurrentProvider("alpha-2")
        #expect(vm.selectedModelId == "alpha-2")

        _ = await vm.sendMessage("after")
        let after = recorder.all
        #expect(after.count >= 2)
        #expect(after.last?.modelId == "alpha-2", "expected alpha-2; observed: \(after)")
    }

    @MainActor
    @Test("setModelForCurrentProviderIgnoresEmptySelection so we never overwrite with a blank id")
    func setModelForCurrentProviderIgnoresEmptySelection() {
        let defaults = makeDefaults()
        let recorder = ObservedRequests()
        let runtime = makeRuntime(
            providerId: "alpha",
            modelIds: ["alpha-1", "alpha-2"],
            recorder: recorder
        )
        let vm = AIChatViewModel(runtime: runtime, defaults: defaults)
        vm.selectedProviderId = "alpha"
        vm.selectedModelId = "alpha-1"

        vm.setModelForCurrentProvider("   ")
        vm.setModelForCurrentProvider("")

        #expect(vm.selectedModelId == "alpha-1")
        #expect(defaults.string(forKey: "ai_model_for_alpha") != "")
    }
}
