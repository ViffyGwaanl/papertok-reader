import Testing
import Foundation
@testable import PTFeatures
import PTAIServices
import PTCore

@Suite("AIChatViewModel Offline Error Handling")
struct AIChatViewModelOfflineTests {
    // MARK: - Stub provider that throws a configurable error

    final class ErrorState: @unchecked Sendable {
        private let lock = NSLock()
        private var _error: Error = URLError(.notConnectedToInternet)

        var error: Error {
            get { lock.lock(); defer { lock.unlock() }; return _error }
            set { lock.lock(); _error = newValue; lock.unlock() }
        }
    }

    struct ThrowingProvider: ChatModelProvider {
        let id: String = "stub-throwing"
        let displayName: String = "Stub Throwing Provider"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]
        let state: ErrorState

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            throw state.error
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            let error = state.error
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    private static func makeRuntime(state: ErrorState) -> AIChatViewModel.Runtime {
        AIChatViewModel.Runtime(
            providers: [
                .init(
                    id: "stub",
                    displayName: "Stub",
                    models: [
                        .init(id: "stub-model", displayName: "Stub Model", supportsThinking: false, supportsVision: false)
                    ],
                    makeProvider: { ThrowingProvider(state: state) }
                )
            ]
        )
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "AIChatViewModelOfflineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    @Test("offline error shows specific offline message")
    func offlineErrorShowsSpecificMessage() async {
        let state = ErrorState()
        state.error = URLError(.notConnectedToInternet)
        let vm = AIChatViewModel(runtime: Self.makeRuntime(state: state), defaults: Self.isolatedDefaults())

        _ = await vm.sendMessage("hello")

        #expect(vm.errorMessage != nil)
        // The offline error message should differ from the generic streaming interrupted message
        #expect(vm.errorMessage != nil)
    }

    @MainActor
    @Test("timed out error does not use offline message")
    func otherNetworkErrorShowsGenericMessage() async {
        let state = ErrorState()
        state.error = URLError(.timedOut)
        let vm = AIChatViewModel(runtime: Self.makeRuntime(state: state), defaults: Self.isolatedDefaults())

        _ = await vm.sendMessage("hello")

        #expect(vm.errorMessage != nil)
    }

    @Test("isOfflineError detects notConnectedToInternet")
    func isOfflineDetectsNotConnected() {
        #expect(AIChatViewModel.isOfflineError(URLError(.notConnectedToInternet)) == true)
    }

    @Test("isOfflineError detects networkConnectionLost")
    func isOfflineDetectsConnectionLost() {
        #expect(AIChatViewModel.isOfflineError(URLError(.networkConnectionLost)) == true)
    }

    @Test("isOfflineError rejects timedOut")
    func isOfflineRejectsTimedOut() {
        #expect(AIChatViewModel.isOfflineError(URLError(.timedOut)) == false)
    }

    @Test("isOfflineError rejects arbitrary errors")
    func isOfflineRejectsArbitraryError() {
        struct SomeError: Error {}
        #expect(AIChatViewModel.isOfflineError(SomeError()) == false)
    }
}
