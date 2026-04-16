import Testing
import Foundation
@testable import PTFeatures
import PTAIServices
import PTCore

/// W5.3 — AI Provider consolidation. Verifies the chat VM re-resolves the
/// effective provider/model at send time from the detailed settings catalog,
/// reacts to configuration-change notifications, and exposes reactive display
/// names for the chip read-only chip.
@Suite("AIChatViewModel Provider Resolution (W5.3)")
struct AIChatViewModelProviderResolutionTests {
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
        let modelMarker: String
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
        modelId: String,
        recorder: ObservedRequests
    ) -> AIChatViewModel.Runtime {
        AIChatViewModel.Runtime(
            providers: [
                .init(
                    id: providerId,
                    displayName: providerId.capitalized,
                    models: [
                        .init(
                            id: modelId,
                            displayName: modelId,
                            supportsThinking: false,
                            supportsVision: false
                        )
                    ],
                    makeProvider: {
                        StubProvider(
                            id: providerId,
                            displayName: providerId.capitalized,
                            modelMarker: modelId,
                            recorder: recorder
                        )
                    }
                )
            ]
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AIChatProviderResolutionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - A. Resolve at send time

    @MainActor
    @Test("resolvesProviderAtSendTime uses the latest UserDefaults when an explicit resolver is wired")
    func resolvesProviderAtSendTime() async {
        let defaults = makeDefaults()
        let recorder = ObservedRequests()

        // Runtime #1: "alpha" — initial runtime the VM is constructed with.
        let initialRuntime = makeRuntime(providerId: "alpha", modelId: "alpha-1", recorder: recorder)
        // Runtime #2: "beta" — what the resolver should return at send time.
        let refreshedRuntime = makeRuntime(providerId: "beta", modelId: "beta-1", recorder: recorder)

        let resolver: @MainActor @Sendable () -> (runtime: AIChatViewModel.Runtime, selection: AIChatViewModel.RuntimeSelection)? = {
            (refreshedRuntime, AIChatViewModel.RuntimeSelection(providerId: "beta", modelId: "beta-1"))
        }

        let vm = AIChatViewModel(
            runtime: initialRuntime,
            defaults: defaults,
            sendTimeResolver: resolver
        )

        #expect(vm.selectedProviderId == "alpha")

        _ = await vm.sendMessage("Hi")

        let observed = recorder.all
        #expect(observed.count >= 1)
        #expect(observed.first?.providerId == "beta", "Send should use the resolver-supplied provider id; observed: \(observed)")
        #expect(observed.first?.modelId == "beta-1")
    }

    // MARK: - B. Subscribe to configuration-change notification

    @MainActor
    @Test("subscribesToConfigChangeNotification refreshes runtime from the resolver")
    func subscribesToConfigChangeNotification() async {
        let defaults = makeDefaults()
        let recorder = ObservedRequests()
        let initialRuntime = makeRuntime(providerId: "alpha", modelId: "alpha-1", recorder: recorder)

        // Use a mutable box so the resolver can flip which runtime it returns.
        final class Holder: @unchecked Sendable {
            let lock = NSLock()
            var next: (AIChatViewModel.Runtime, AIChatViewModel.RuntimeSelection)?
            func set(_ value: (AIChatViewModel.Runtime, AIChatViewModel.RuntimeSelection)?) {
                lock.lock(); defer { lock.unlock() }
                next = value
            }
            func get() -> (AIChatViewModel.Runtime, AIChatViewModel.RuntimeSelection)? {
                lock.lock(); defer { lock.unlock() }
                return next
            }
        }
        let holder = Holder()

        let resolver: @MainActor @Sendable () -> (runtime: AIChatViewModel.Runtime, selection: AIChatViewModel.RuntimeSelection)? = {
            holder.get().map { ($0.0, $0.1) }
        }

        let vm = AIChatViewModel(
            runtime: initialRuntime,
            defaults: defaults,
            sendTimeResolver: resolver
        )

        #expect(vm.displayedProviderName == "Alpha")
        #expect(vm.displayedModelName == "alpha-1")

        // Now flip the resolver to return gamma and post the notification.
        let gammaRuntime = makeRuntime(providerId: "gamma", modelId: "gamma-9", recorder: recorder)
        holder.set((gammaRuntime, .init(providerId: "gamma", modelId: "gamma-9")))

        NotificationCenter.default.post(
            name: StoredAIProviderCatalog.configurationDidChangeNotification,
            object: nil
        )

        // Give the run loop a chance to drain the notification observer.
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(vm.selectedProviderId == "gamma", "VM should refresh selection after configurationDidChange")
        #expect(vm.selectedModelId == "gamma-9")
        #expect(vm.displayedProviderName == "Gamma")
        #expect(vm.displayedModelName == "gamma-9")
    }

    // MARK: - C. Detailed settings effective after save

    @MainActor
    @Test("detailedSettingsEffectiveAfterSave applies the new selection to subsequent sends")
    func detailedSettingsEffectiveAfterSave() async {
        let defaults = makeDefaults()
        let recorder = ObservedRequests()

        let initialRuntime = makeRuntime(providerId: "alpha", modelId: "alpha-1", recorder: recorder)
        let savedRuntime = makeRuntime(providerId: "beta", modelId: "beta-2", recorder: recorder)

        final class Holder: @unchecked Sendable {
            let lock = NSLock()
            var value: (AIChatViewModel.Runtime, AIChatViewModel.RuntimeSelection)
            init(_ value: (AIChatViewModel.Runtime, AIChatViewModel.RuntimeSelection)) {
                self.value = value
            }
            func set(_ value: (AIChatViewModel.Runtime, AIChatViewModel.RuntimeSelection)) {
                lock.lock(); defer { lock.unlock() }
                self.value = value
            }
            func get() -> (AIChatViewModel.Runtime, AIChatViewModel.RuntimeSelection) {
                lock.lock(); defer { lock.unlock() }
                return value
            }
        }
        let holder = Holder((initialRuntime, .init(providerId: "alpha", modelId: "alpha-1")))

        let resolver: @MainActor @Sendable () -> (runtime: AIChatViewModel.Runtime, selection: AIChatViewModel.RuntimeSelection)? = {
            let pair = holder.get()
            return (pair.0, pair.1)
        }

        let vm = AIChatViewModel(
            runtime: initialRuntime,
            defaults: defaults,
            sendTimeResolver: resolver
        )

        _ = await vm.sendMessage("first")
        let firstObserved = recorder.all
        #expect(firstObserved.first?.providerId == "alpha")

        // Simulate a save in the detailed view — swap what the resolver returns
        // and publish the notification as the detail view would.
        holder.set((savedRuntime, .init(providerId: "beta", modelId: "beta-2")))
        StoredAIProviderCatalog.postConfigurationDidChange()
        try? await Task.sleep(nanoseconds: 20_000_000)

        _ = await vm.sendMessage("second")
        let allObserved = recorder.all
        #expect(allObserved.count >= 2, "Expected two recorded requests, got \(allObserved.count)")
        let last = allObserved.last
        #expect(last?.providerId == "beta", "Second send should use beta provider; observed: \(allObserved)")
        #expect(last?.modelId == "beta-2")
    }

    // MARK: - D. displayedProviderName/displayedModelName default to current selection

    @MainActor
    @Test("displayedProviderName defaults to the current selection when no catalog is wired")
    func displayedPropertiesFallBackToRuntime() {
        let defaults = makeDefaults()
        let recorder = ObservedRequests()
        let runtime = makeRuntime(providerId: "solo", modelId: "solo-1", recorder: recorder)
        let vm = AIChatViewModel(runtime: runtime, defaults: defaults)
        #expect(vm.displayedProviderName == "Solo")
        #expect(vm.displayedModelName == "solo-1")
    }
}
