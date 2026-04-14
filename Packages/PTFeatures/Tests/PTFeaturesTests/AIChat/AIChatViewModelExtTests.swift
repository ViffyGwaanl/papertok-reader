import Testing
import Foundation
@testable import PTFeatures
import PTAIServices
import PTCore

@Suite("AIChatViewModel Extensions")
struct AIChatViewModelExtTests {
    struct MockReaderBridge: BookContentBridgeProtocol {
        func tableOfContentsJSON() async throws -> String {
            #"{"chapters":[{"title":"Introduction","href":"chapter-1"}]}"#
        }

        func chapterContent(href: String) async throws -> String { "Introduction body" }
        func fullText() async throws -> String { "Short body" }
        func search(query: String) async throws -> String {
            #"{"results":[{"href":"chapter-1"}]}"#
        }
    }

    actor RequestRecorder {
        private(set) var lastRequest: ChatRequest?

        func record(_ request: ChatRequest) {
            lastRequest = request
        }
    }

    struct MockStreamProvider: ChatModelProvider {
        let id: String
        let displayName: String
        let supportedCapabilities: Set<ModelCapability>
        let chunks: [ChatStreamChunk]
        let followupChunks: [ChatStreamChunk]
        let requestObserver: @Sendable (ChatRequest) -> Void

        init(
            id: String = "mock",
            displayName: String = "Mock Provider",
            supportedCapabilities: Set<ModelCapability> = [.chat, .streaming, .toolCalling],
            chunks: [ChatStreamChunk],
            followupChunks: [ChatStreamChunk] = [],
            requestObserver: @escaping @Sendable (ChatRequest) -> Void = { _ in }
        ) {
            self.id = id
            self.displayName = displayName
            self.supportedCapabilities = supportedCapabilities
            self.chunks = chunks
            self.followupChunks = followupChunks
            self.requestObserver = requestObserver
        }

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(message: .assistant("unused"))
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            let chunks: [ChatStreamChunk]
            if request.messages.last?.role == .tool, followupChunks.isEmpty == false {
                chunks = followupChunks
            } else {
                chunks = self.chunks
            }
            requestObserver(request)
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
            let value = arguments["value"] as? Int ?? 0
            return ToolResult(content: #"{"status":"ok","echo":\#(value)}"#)
        }
    }

    enum MockToolExecutionError: LocalizedError {
        case exploded

        var errorDescription: String? {
            "Mock tool exploded"
        }
    }

    struct MockThrowingSafeTool: AITool {
        static let name = "mock_throwing_tool"
        static let description = "A safe mock tool that throws."
        static let category = ToolCategory.utility
        static let riskLevel = ToolRiskLevel.safe

        func execute(arguments: [String : Any], context: ToolContext) async throws -> ToolResult {
            throw MockToolExecutionError.exploded
        }
    }

    struct MockJSONErrorTool: AITool {
        static let name = "mock_json_error_tool"
        static let description = "A safe mock tool that returns JSON errors."
        static let category = ToolCategory.utility
        static let riskLevel = ToolRiskLevel.safe

        func execute(arguments: [String : Any], context: ToolContext) async throws -> ToolResult {
            ToolResult(content: #"{"error":"missing query"}"#, isError: true)
        }
    }

    enum MockStreamError: LocalizedError {
        case failed

        var errorDescription: String? {
            "Mock stream failure"
        }
    }

    struct MockFailingStreamProvider: ChatModelProvider {
        let error: Error
        let id: String = "mock-failing"
        let displayName: String = "Mock Failing Provider"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]

        init(error: Error = MockStreamError.failed) {
            self.error = error
        }

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            throw error
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
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
        followupChunks: [ChatStreamChunk] = [],
        extras: [any AITool] = [],
        toolContext: ToolContext = ToolContext(),
        requestObserver: @escaping @Sendable (ChatRequest) -> Void = { _ in }
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
                    makeProvider: {
                        MockStreamProvider(
                            chunks: chunks,
                            followupChunks: followupChunks,
                            requestObserver: requestObserver
                        )
                    }
                )
            ],
            toolRegistry: ToolRegistry(extras: extras),
            toolContext: toolContext
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

        let success = await vm.sendMessage("Hi")

        #expect(success)
        #expect(vm.isStreaming == false)
        let assistantMessages = vm.messages.filter { $0.role == .assistant }
        #expect(assistantMessages.count == 1)
        #expect(assistantMessages.first?.textContent == "Hello world")
    }

    @MainActor
    @Test("sendMessage returns false and exposes provider errors")
    func sendMessageReturnsFalseOnProviderFailure() async {
        let runtime = AIChatViewModel.Runtime(
            providers: [
                .init(
                    id: "mock-failing",
                    displayName: "Mock Failing Provider",
                    models: [
                        .init(
                            id: "mock-model",
                            displayName: "Mock Model",
                            supportsThinking: false,
                            supportsVision: false
                        )
                    ],
                    makeProvider: { MockFailingStreamProvider() }
                )
            ]
        )
        let vm = AIChatViewModel(runtime: runtime)

        let success = await vm.sendMessage("Hi")

        #expect(success == false)
        #expect(vm.errorMessage == localizedCatalogString("errors.ai.streaming_interrupted"))
        #expect(vm.messages.filter { $0.role == .user }.count == 1)
        #expect(vm.messages.contains(where: { $0.role == .assistant }) == false)
    }

    @MainActor
    @Test("sendMessage preserves localized provider failures when the provider supplies them")
    func sendMessagePreservesLocalizedProviderFailure() async {
        let runtime = AIChatViewModel.Runtime(
            providers: [
                .init(
                    id: "mock-provider-error",
                    displayName: "Mock Provider Error",
                    models: [
                        .init(
                            id: "mock-model",
                            displayName: "Mock Model",
                            supportsThinking: false,
                            supportsVision: false
                        )
                    ],
                    makeProvider: {
                        MockFailingStreamProvider(
                            error: ProviderError.authenticationFailed("missing api key")
                        )
                    }
                )
            ]
        )
        let vm = AIChatViewModel(runtime: runtime)

        let success = await vm.sendMessage("Hi")

        #expect(success == false)
        #expect(vm.errorMessage == AppLocalization.string("errors.ai.no_api_key"))
        #expect(vm.messages.contains(where: { $0.role == .assistant }) == false)
    }

    @MainActor
    @Test("sendMessage includes current image attachments in the user message and clears the composer")
    func sendMessageIncludesImageAttachments() async throws {
        let recorder = RequestRecorder()
        let runtime = makeRuntime(
            chunks: [
                .init(delta: .text("done"), finishReason: .stop)
            ],
            requestObserver: { request in
                Task { await recorder.record(request) }
            }
        )
        let vm = AIChatViewModel(runtime: runtime)
        vm.addAttachment(.init(type: .image, name: "photo.jpg", data: Data([0x89, 0x50, 0x4E, 0x47])))

        await vm.sendMessage("Analyze this")

        let request = try #require(await recorder.lastRequest)
        let userMessage = try #require(request.messages.last(where: { $0.role == .user }))
        #expect(userMessage.content.contains(where: {
            if case .imageBase64 = $0 { return true }
            return false
        }))
        #expect(vm.attachments.isEmpty)
    }

    @MainActor
    @Test("sendMessage includes file attachment placeholders using localized formatting")
    func sendMessageIncludesFileAttachments() async throws {
        let recorder = RequestRecorder()
        let runtime = makeRuntime(
            chunks: [
                .init(delta: .text("done"), finishReason: .stop)
            ],
            requestObserver: { request in
                Task { await recorder.record(request) }
            }
        )
        let vm = AIChatViewModel(runtime: runtime)
        vm.addAttachment(.init(type: .file, name: "notes.pdf", data: Data()))

        await vm.sendMessage("Analyze this")

        let request = try #require(await recorder.lastRequest)
        let userMessage = try #require(request.messages.last(where: { $0.role == .user }))
        let localizedPlaceholder = localizedCatalogFormat("ai.chat.attachment_file_format", "notes.pdf")

        #expect(userMessage.content.contains(where: {
            guard case .text(let text) = $0 else { return false }
            return text == localizedPlaceholder
        }))
        #expect(vm.attachments.isEmpty)
    }

    @MainActor
    @Test("safe tool calls execute through tool registry")
    func safeToolCallsExecute() async {
        let runtime = makeRuntime(
            chunks: [
                .init(delta: .toolCall(index: 0, id: "tool-1", name: "mock_safe_tool", arguments: "{\"value\":7}"), finishReason: .toolCalls)
            ],
            followupChunks: [
                .init(delta: .text("Tool finished"), finishReason: .stop)
            ],
            extras: [MockSafeTool()]
        )
        let vm = AIChatViewModel(runtime: runtime)

        await vm.sendMessage("Use a tool")

        #expect(vm.pendingApprovals.isEmpty)
        let toolMessages = vm.messages.filter { $0.role == .tool }
        #expect(toolMessages.count == 1)
        #expect(toolMessages.first?.textContent?.contains("\"status\":\"ok\"") == true)
        #expect(vm.messages.last?.role == .assistant)
        #expect(vm.messages.last?.textContent == "Tool finished")
    }

    @MainActor
    @Test("safe tool failures show only the localized summary")
    func safeToolFailuresShowOnlyLocalizedSummary() async {
        let runtime = makeRuntime(
            chunks: [
                .init(delta: .toolCall(index: 0, id: "tool-3", name: "mock_throwing_tool", arguments: "{\"value\":7}"), finishReason: .toolCalls)
            ],
            followupChunks: [
                .init(delta: .text("Handled"), finishReason: .stop)
            ],
            extras: [MockThrowingSafeTool()]
        )
        let vm = AIChatViewModel(runtime: runtime)

        await vm.sendMessage("Use a failing tool")

        let toolMessages = vm.messages.filter { $0.role == .tool }
        #expect(toolMessages.count == 1)
        let toolText = toolMessages.first?.textContent ?? ""
        #expect(toolText == localizedCatalogString("errors.ai.tool_failed"))
        #expect(toolText.contains("Mock tool exploded") == false)
        #expect(vm.messages.last?.role == .assistant)
        #expect(vm.messages.last?.textContent == "Handled")
    }

    @MainActor
    @Test("JSON-shaped tool failures are hidden behind the localized summary")
    func jsonToolFailuresHideMachinePayloads() async {
        let runtime = makeRuntime(
            chunks: [
                .init(delta: .toolCall(index: 0, id: "tool-4", name: "mock_json_error_tool", arguments: "{\"query\":\"\"}"), finishReason: .toolCalls)
            ],
            followupChunks: [
                .init(delta: .text("Handled"), finishReason: .stop)
            ],
            extras: [MockJSONErrorTool()]
        )
        let vm = AIChatViewModel(runtime: runtime)

        await vm.sendMessage("Use a failing tool")

        let toolMessages = vm.messages.filter { $0.role == .tool }
        #expect(toolMessages.count == 1)
        let toolText = toolMessages.first?.textContent ?? ""
        #expect(toolText == localizedCatalogString("errors.ai.tool_failed"))
        #expect(toolText.contains("missing query") == false)
        #expect(vm.messages.last?.role == .assistant)
        #expect(vm.messages.last?.textContent == "Handled")
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

    @MainActor
    @Test("sendMessage advertises only tools that are runnable in the current context")
    func sendMessageAdvertisesRunnableToolsOnly() async {
        let recorder = RequestRecorder()
        let runtime = makeRuntime(
            chunks: [.init(delta: .text("ok"), finishReason: .stop)],
            requestObserver: { request in
                Task { await recorder.record(request) }
            }
        )
        let vm = AIChatViewModel(runtime: runtime)

        await vm.sendMessage("Hi")

        let toolNames = Set((await recorder.lastRequest?.tools ?? []).map(\.name))
        #expect(toolNames.contains("spawn_sub_agent") == false)
        #expect(toolNames.contains("shortcuts_run") == false)
        #expect(toolNames.contains("memory_read") == false)
        #expect(toolNames.contains("current_book_toc") == false)
        #expect(toolNames.contains("current_time"))
    }

    @MainActor
    @Test("sendMessage advertises reader-session tools when runtime has an active reader session")
    func sendMessageAdvertisesReaderSessionTools() async {
        let recorder = RequestRecorder()
        let readerSessionStore = ReaderSessionContextStore()
        readerSessionStore.update(
            ReaderSessionSnapshot(
                bookId: 7,
                readingProgress: 0.33,
                chapterTitle: "Introduction",
                locationHref: "chapter-1",
                contentBridgeProvider: { MockReaderBridge() }
            )
        )
        let runtime = makeRuntime(
            chunks: [.init(delta: .text("ok"), finishReason: .stop)],
            toolContext: ToolContext(readerSessionStore: readerSessionStore),
            requestObserver: { request in
                Task { await recorder.record(request) }
            }
        )
        let vm = AIChatViewModel(runtime: runtime)

        await vm.sendMessage("Hi")

        let toolNames = Set((await recorder.lastRequest?.tools ?? []).map(\.name))
        #expect(toolNames.contains("current_book_toc"))
        #expect(toolNames.contains("current_chapter_content"))
        #expect(toolNames.contains("current_book_fulltext"))
        #expect(toolNames.contains("chapter_content_by_href"))
        #expect(toolNames.contains("book_content_search"))
        #expect(toolNames.contains("resolve_cfi") == false)
        #expect(toolNames.contains("semantic_search_current_book") == false)
    }
}

private func localizedCatalogString(_ key: String, locale: Locale = .autoupdatingCurrent) -> String {
    String(localized: String.LocalizationValue(key), bundle: localizedCatalogBundle(), locale: locale)
}

private func localizedCatalogFormat(_ key: String, locale: Locale = .autoupdatingCurrent, _ arguments: CVarArg...) -> String {
    String(format: localizedCatalogString(key, locale: locale), locale: locale, arguments: arguments)
}

private func localizedCatalogBundle() -> Bundle {
    let bundles = Bundle.allBundles + Bundle.allFrameworks

    if Bundle.main.bundleURL.pathExtension == "app" {
        return .main
    }
    if let appBundle = bundles.first(where: { $0.bundleIdentifier == "ai.papertok.paperreader" }) {
        return appBundle
    }
    let candidateDirectories = Set(bundles.map { $0.bundleURL.deletingLastPathComponent() })
    for directory in candidateDirectories {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { continue }

        for candidateURL in urls where candidateURL.pathExtension == "app" {
            if let appBundle = Bundle(url: candidateURL),
               appBundle.bundleIdentifier == "ai.papertok.paperreader" {
                return appBundle
            }
        }
    }
    return bundles.first(where: { $0.bundleURL.pathExtension == "app" }) ?? .main
}
