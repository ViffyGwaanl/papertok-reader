import Testing
import Foundation
@testable import PTFeatures
import PTAIServices

@Suite("AIChatViewModel Extensions")
struct AIChatViewModelExtTests {
    struct MockStreamProvider: ChatModelProvider {
        let id: String
        let displayName: String
        let supportedCapabilities: Set<ModelCapability>
        let chunks: [ChatStreamChunk]

        init(
            id: String = "mock",
            displayName: String = "Mock Provider",
            supportedCapabilities: Set<ModelCapability> = [.chat, .streaming, .toolCalling],
            chunks: [ChatStreamChunk]
        ) {
            self.id = id
            self.displayName = displayName
            self.supportedCapabilities = supportedCapabilities
            self.chunks = chunks
        }

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(message: .assistant("unused"))
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            let chunks = self.chunks
            return AsyncThrowingStream { continuation in
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    struct MockSafeTool: AITool {
        static let name = "mock_safe_tool"
        static let description = "A safe mock tool."
        static let category = ToolCategory.utility
        static let riskLevel = ToolRiskLevel.safe

        func execute(arguments: [String : Any], context: ToolContext) async throws -> ToolResult {
            ToolResult(content: "{\"status\":\"ok\",\"echo\":\(arguments[\"value\"] as? Int ?? 0)}")
        }
    }

    struct MockDangerousTool: AITool {
        static let name = "mock_dangerous_tool"
        static let description = "A dangerous mock tool."
        static let category = ToolCategory.utility
        static let riskLevel = ToolRiskLevel.dangerous

        func execute(arguments: [String : Any], context: ToolContext) async throws -> ToolResult {
            ToolResult(content: "{\"status\":\"should_not_run\"}")
        }
    }

    @MainActor
    private func makeRuntime(
        chunks: [ChatStreamChunk],
        extras: [any AITool] = []
    ) -> AIChatViewModel.Runtime {
        AIChatViewModel.Runtime(
            providers: [
                .init(
                    id: "mock",
                    displayName: "Mock Provider",
                    models: [
                        .init(
                            id: "mock-model",
                            displayName: "Mock Model",
                            supportsThinking: false,
                            supportsVision: false
                        )
                    ],
                    makeProvider: { MockStreamProvider(chunks: chunks) }
                )
            ],
            toolRegistry: ToolRegistry(extras: extras),
            toolContext: ToolContext()
        )
    }

    @MainActor
    @Test("attachments initially empty")
    func attachmentsInitiallyEmpty() {
        let vm = AIChatViewModel()
        #expect(vm.attachments.isEmpty)
    }

    @MainActor
    @Test("addAttachment increases count")
    func addAttachment() {
        let vm = AIChatViewModel()
        vm.addAttachment(.init(type: .image, name: "photo.jpg", data: Data()))
        #expect(vm.attachments.count == 1)
    }

    @MainActor
    @Test("clearAttachments empties list")
    func clearAttachments() {
        let vm = AIChatViewModel()
        vm.addAttachment(.init(type: .image, name: "photo.jpg", data: Data()))
        vm.clearAttachments()
        #expect(vm.attachments.isEmpty)
    }

    @MainActor
    @Test("removeAttachment removes specific item")
    func removeAttachment() {
        let vm = AIChatViewModel()
        vm.addAttachment(.init(type: .image, name: "a.jpg", data: Data()))
        vm.addAttachment(.init(type: .file, name: "b.pdf", data: Data()))
        let idToRemove = vm.attachments[0].id
        vm.removeAttachment(id: idToRemove)
        #expect(vm.attachments.count == 1)
        #expect(vm.attachments[0].name == "b.pdf")
    }

    @MainActor
    @Test("provider options are populated from runtime")
    func selectedProviderDefault() {
        let vm = AIChatViewModel()
        #expect(vm.providerOptions.isEmpty == false)
        #expect(vm.selectedProviderId == vm.providerOptions.first?.id)
        #expect(vm.selectedModelId == vm.providerOptions.first?.models.first?.id)
    }

    @MainActor
    @Test("appendStreamToken accumulates text")
    func streamTokenAccumulation() {
        let vm = AIChatViewModel()
        vm.appendStreamToken("Hello")
        vm.appendStreamToken(" world")
        #expect(vm.currentStreamText == "Hello world")
        #expect(vm.streamingTokens.count == 2)
    }

    @MainActor
    @Test("finalizeStream creates assistant message and resets")
    func finalizeStream() {
        let vm = AIChatViewModel()
        vm.isStreaming = true
        vm.appendStreamToken("Response text")
        vm.finalizeStream()
        #expect(vm.currentStreamText.isEmpty)
        #expect(vm.streamingTokens.isEmpty)
        #expect(vm.isStreaming == false)
        // The assistant message should be in the conversation tree
        let messages = vm.messages
        let assistantMessages = messages.filter { $0.role == .assistant }
        #expect(assistantMessages.count == 1)
        #expect(assistantMessages.first?.textContent == "Response text")
    }

    @MainActor
    @Test("requestApproval adds to pending list")
    func toolApproval() {
        let vm = AIChatViewModel()
        vm.requestApproval(toolName: "calendar_write", toolCallId: "tc1", arguments: "{}")
        #expect(vm.pendingApprovals.count == 1)
        #expect(vm.pendingApprovals[0].toolName == "calendar_write")
        #expect(vm.pendingApprovals[0].isApproved == nil)
    }

    @MainActor
    @Test("resolveApproval updates status")
    func resolveApproval() {
        let vm = AIChatViewModel()
        vm.requestApproval(toolName: "test", toolCallId: "tc1", arguments: "{}")
        let id = vm.pendingApprovals[0].id
        vm.resolveApproval(id: id, approved: true)
        #expect(vm.pendingApprovals[0].isApproved == true)
    }

    @MainActor
    @Test("clearConversation resets all state")
    func clearConversation() {
        let vm = AIChatViewModel()
        vm.addAttachment(.init(type: .image, name: "test.jpg", data: Data()))
        vm.appendStreamToken("test")
        vm.requestApproval(toolName: "test", toolCallId: "tc1", arguments: "{}")
        vm.clearConversation()
        #expect(vm.attachments.isEmpty)
        #expect(vm.currentStreamText.isEmpty)
        #expect(vm.streamingTokens.isEmpty)
        #expect(vm.pendingApprovals.isEmpty)
    }

    @MainActor
    @Test("sendMessage streams assistant text with configured provider")
    func sendMessageStreamsAssistantText() async {
        let runtime = makeRuntime(chunks: [
            .init(delta: .text("Hello")),
            .init(delta: .text(" world"), finishReason: .stop)
        ])
        let vm = AIChatViewModel(runtime: runtime)

        await vm.sendMessage("Hi")

        #expect(vm.isStreaming == false)
        let assistantMessages = vm.messages.filter { $0.role == .assistant }
        #expect(assistantMessages.count == 1)
        #expect(assistantMessages.first?.textContent == "Hello world")
    }

    @MainActor
    @Test("safe tool calls execute through tool registry")
    func safeToolCallsExecute() async {
        let runtime = makeRuntime(
            chunks: [
                .init(delta: .toolCall(index: 0, id: "tool-1", name: "mock_safe_tool", arguments: "{\"value\":7}"), finishReason: .toolCalls)
            ],
            extras: [MockSafeTool()]
        )
        let vm = AIChatViewModel(runtime: runtime)

        await vm.sendMessage("Use a tool")

        #expect(vm.pendingApprovals.isEmpty)
        let toolMessages = vm.messages.filter { $0.role == .tool }
        #expect(toolMessages.count == 1)
        #expect(toolMessages.first?.textContent?.contains("\"status\":\"ok\"") == true)
    }

    @MainActor
    @Test("dangerous tool calls are queued for approval")
    func dangerousToolCallsQueueApproval() async {
        let runtime = makeRuntime(
            chunks: [
                .init(delta: .toolCall(index: 0, id: "tool-2", name: "mock_dangerous_tool", arguments: "{\"value\":1}"), finishReason: .toolCalls)
            ],
            extras: [MockDangerousTool()]
        )
        let vm = AIChatViewModel(runtime: runtime)

        await vm.sendMessage("Do something risky")

        #expect(vm.pendingApprovals.count == 1)
        #expect(vm.pendingApprovals[0].toolName == "mock_dangerous_tool")
        #expect(vm.messages.contains(where: { $0.role == .tool }) == false)
    }
}
