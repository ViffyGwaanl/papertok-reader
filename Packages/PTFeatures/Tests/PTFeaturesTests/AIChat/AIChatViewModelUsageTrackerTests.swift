import Testing
import Foundation
@testable import PTFeatures
import PTAIServices
import PTCore

@Suite("AIChatViewModel usage tracker wiring (W2.3c)")
struct AIChatViewModelUsageTrackerTests {
    struct UsageEmittingProvider: ChatModelProvider {
        let id: String = "stub-usage"
        let displayName: String = "Stub Usage"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]
        let usage: TokenUsage

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(message: .assistant("ok"), usage: usage)
        }
        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(ChatStreamChunk(delta: .text("hello")))
                continuation.yield(ChatStreamChunk(delta: .text(""), finishReason: .stop, usage: usage))
                continuation.finish()
            }
        }
    }

    struct DelayedUsageProvider: ChatModelProvider {
        let id: String = "stub-delayed-usage"
        let displayName: String = "Stub Delayed Usage"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]
        let delayNanos: UInt64
        let usage: TokenUsage

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(message: .assistant("ok"), usage: usage)
        }
        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            let usage = self.usage
            let delayNanos = self.delayNanos
            return AsyncThrowingStream { continuation in
                let task = Task {
                    continuation.yield(ChatStreamChunk(delta: .text("partial")))
                    try? await Task.sleep(nanoseconds: delayNanos)
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    continuation.yield(ChatStreamChunk(delta: .text(""), finishReason: .stop, usage: usage))
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    struct ErrorProvider: ChatModelProvider {
        let id: String = "stub-error"
        let displayName: String = "Stub Error"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]
        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            throw ProviderError.serverError(statusCode: 500, message: "boom")
        }
        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: ProviderError.serverError(statusCode: 500, message: "boom"))
            }
        }
    }

    private static func makeRuntime(_ make: @Sendable @escaping () -> any ChatModelProvider) -> AIChatViewModel.Runtime {
        AIChatViewModel.Runtime(
            providers: [
                .init(
                    id: "stub",
                    displayName: "Stub",
                    models: [.init(id: "gpt-4o", displayName: "gpt-4o", supportsThinking: false, supportsVision: false)],
                    makeProvider: make
                )
            ]
        )
    }

    private static func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageTrackerVMTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "AIChatViewModelUsageTrackerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    @Test("usageTrackerReceivesRecordAfterSuccessfulCall")
    func usageTrackerReceivesRecordAfterSuccessfulCall() async {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tracker = UsageTracker(directory: dir)
        let usage = TokenUsage(promptTokens: 11, completionTokens: 22, totalTokens: 33)
        let vm = AIChatViewModel(
            runtime: Self.makeRuntime({ UsageEmittingProvider(usage: usage) }),
            defaults: Self.isolatedDefaults(),
            usageTracker: tracker
        )

        _ = await vm.sendMessage("hi")

        let records = await tracker.allRecords()
        #expect(records.count == 1)
        #expect(records.first?.modelId == "gpt-4o")
        #expect(records.first?.promptTokens == 11)
        #expect(records.first?.completionTokens == 22)
    }

    @MainActor
    @Test("usageTrackerNotCalledOnCancellation")
    func usageTrackerNotCalledOnCancellation() async {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tracker = UsageTracker(directory: dir)
        let usage = TokenUsage(promptTokens: 5, completionTokens: 5, totalTokens: 10)
        let vm = AIChatViewModel(
            runtime: Self.makeRuntime({ DelayedUsageProvider(delayNanos: 500_000_000, usage: usage) }),
            defaults: Self.isolatedDefaults(),
            usageTracker: tracker
        )

        let sendTask = Task { @MainActor in
            await vm.sendMessage("hi")
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        vm.stopStreaming()
        _ = await sendTask.value

        let records = await tracker.allRecords()
        #expect(records.isEmpty)
    }

    @MainActor
    @Test("usageTrackerNotCalledOnProviderError")
    func usageTrackerNotCalledOnProviderError() async {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tracker = UsageTracker(directory: dir)
        let vm = AIChatViewModel(
            runtime: Self.makeRuntime({ ErrorProvider() }),
            defaults: Self.isolatedDefaults(),
            usageTracker: tracker
        )

        _ = await vm.sendMessage("hi")

        let records = await tracker.allRecords()
        #expect(records.isEmpty)
    }
}
