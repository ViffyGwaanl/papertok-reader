import Foundation
import Observation
import PTAIServices

@MainActor @Observable
public final class AIChatViewModel {
    public struct ModelOption: Sendable, Identifiable {
        public let id: String
        public let displayName: String
        public let supportsThinking: Bool
        public let supportsVision: Bool

        public init(id: String, displayName: String, supportsThinking: Bool, supportsVision: Bool) {
            self.id = id
            self.displayName = displayName
            self.supportsThinking = supportsThinking
            self.supportsVision = supportsVision
        }
    }

    public struct ProviderOption: Sendable, Identifiable {
        public let id: String
        public let displayName: String
        public let models: [ModelOption]
        public let makeProvider: @Sendable () -> any ChatModelProvider

        public init(
            id: String,
            displayName: String,
            models: [ModelOption],
            makeProvider: @escaping @Sendable () -> any ChatModelProvider
        ) {
            self.id = id
            self.displayName = displayName
            self.models = models
            self.makeProvider = makeProvider
        }
    }

    public struct Runtime {
        public let providers: [ProviderOption]
        public let toolRegistry: ToolRegistry
        public let toolContext: ToolContext

        public init(
            providers: [ProviderOption],
            toolRegistry: ToolRegistry = .default,
            toolContext: ToolContext = ToolContext()
        ) {
            self.providers = providers
            self.toolRegistry = toolRegistry
            self.toolContext = toolContext
        }

        public static let `default` = Runtime(
            providers: [
                ProviderOption(
                    id: "openai",
                    displayName: "OpenAI",
                    models: [
                        ModelOption(id: "gpt-4.1-mini", displayName: "GPT-4.1 Mini", supportsThinking: false, supportsVision: true),
                        ModelOption(id: "gpt-4.1", displayName: "GPT-4.1", supportsThinking: false, supportsVision: true),
                        ModelOption(id: "gpt-4o", displayName: "GPT-4o", supportsThinking: false, supportsVision: true)
                    ],
                    makeProvider: { OpenAIProvider() }
                ),
                ProviderOption(
                    id: "anthropic",
                    displayName: "Anthropic",
                    models: [
                        ModelOption(id: "claude-sonnet-4-20250514", displayName: "Claude Sonnet 4", supportsThinking: true, supportsVision: true)
                    ],
                    makeProvider: { AnthropicProvider() }
                )
            ]
        )
    }

    private struct PartialToolCall {
        var id: String?
        var name: String?
        var arguments: String = ""

        mutating func merge(id: String?, name: String?, arguments: String?) {
            if let id, id.isEmpty == false {
                self.id = id
            }
            if let name, name.isEmpty == false {
                if let current = self.name, current.isEmpty == false, current != name {
                    self.name = current + name
                } else {
                    self.name = name
                }
            }
            if let arguments, arguments.isEmpty == false {
                self.arguments += arguments
            }
        }
    }

    public var conversationTree: ConversationTree
    public var isStreaming: Bool = false
    public var currentStreamText: String = ""
    public var errorMessage: String?
    public let runtime: Runtime
    private var activeTurnProviderId: String?
    private var activeTurnModelId: String?
    private var isContinuingTurn = false
    private var currentTurnRoundCount = 0
    private var approvalExecutionsInFlight: Set<UUID> = []
    private static let maxToolRoundsPerTurn = 8

    public init(
        systemPrompt: String = "You are a helpful reading assistant.",
        runtime: Runtime = .default
    ) {
        self.conversationTree = ConversationTree(systemPrompt: systemPrompt)
        self.runtime = runtime
        self.selectedProviderId = runtime.providers.first?.id ?? ""
        self.selectedModelId = runtime.providers.first?.models.first?.id ?? ""
    }

    /// Messages in the active conversation branch.
    public var messages: [ChatMessage] {
        conversationTree.activeMessages()
    }

    public var providerOptions: [ProviderOption] {
        runtime.providers
    }

    /// Send a user message and stream the provider response into the active branch.
    @discardableResult
    public func sendMessage(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        guard !isStreaming else { return false }
        guard let providerOption = providerOptions.first(where: { $0.id == selectedProviderId }) else {
            errorMessage = "Selected provider is unavailable."
            return false
        }
        guard providerOption.models.contains(where: { $0.id == selectedModelId }) else {
            errorMessage = "Selected model is unavailable."
            return false
        }
        guard pendingApprovals.isEmpty else {
            errorMessage = "Resolve pending tool approvals before sending another message."
            return false
        }

        errorMessage = nil
        beginTurn(providerId: providerOption.id, modelId: selectedModelId)
        conversationTree.append(ChatMessage(role: .user, content: buildUserContentParts(text: trimmed)))
        clearAttachments()
        await continueCurrentTurn()
        return errorMessage == nil
    }

    /// Add an assistant response (used after streaming completes).
    public func addAssistantMessage(_ text: String) {
        conversationTree.append(.assistant(text))
    }

    /// Clear conversation and start fresh.
    public func clearConversation(systemPrompt: String = "You are a helpful reading assistant.") {
        conversationTree = ConversationTree(systemPrompt: systemPrompt)
        endTurn()
        errorMessage = nil
        pendingApprovals.removeAll()
        attachments.removeAll()
    }

    // MARK: - Attachment Support

    public struct Attachment: Sendable, Identifiable {
        public enum AttachmentType: Sendable { case image, file }
        public let id = UUID()
        public let type: AttachmentType
        public let name: String
        public let data: Data
        public init(type: AttachmentType, name: String, data: Data) {
            self.type = type; self.name = name; self.data = data
        }
    }

    public var attachments: [Attachment] = []

    public func addAttachment(_ attachment: Attachment) {
        attachments.append(attachment)
    }

    public func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    public func clearAttachments() {
        attachments.removeAll()
    }

    // MARK: - Provider Selection

    public var selectedProviderId: String = ""
    public var selectedModelId: String = ""

    // MARK: - Streaming Tokens

    public var streamingTokens: [String] = []

    public func appendStreamToken(_ token: String) {
        streamingTokens.append(token)
        currentStreamText += token
    }

    public func finalizeStream() {
        let text = currentStreamText
        if text.isEmpty == false {
            addAssistantMessage(text)
        }
        currentStreamText = ""
        streamingTokens.removeAll()
        isStreaming = false
    }

    // MARK: - Tool Approval Queue

    public struct PendingToolApproval: Sendable, Identifiable {
        public let id = UUID()
        public let toolName: String
        public let toolCallId: String
        public let arguments: String
        public let riskLevel: ToolRiskLevel
        public var isApproved: Bool? = nil
    }

    public var pendingApprovals: [PendingToolApproval] = []

    public func requestApproval(
        toolName: String,
        toolCallId: String,
        arguments: String,
        riskLevel: ToolRiskLevel = .dangerous
    ) {
        pendingApprovals.append(
            PendingToolApproval(
                toolName: toolName,
                toolCallId: toolCallId,
                arguments: arguments,
                riskLevel: riskLevel
            )
        )
    }

    public func resolveApproval(id: UUID, approved: Bool) {
        if let idx = pendingApprovals.firstIndex(where: { $0.id == id }) {
            pendingApprovals[idx].isApproved = approved
            Task { await processApproval(id: id) }
        }
    }

    private func continueCurrentTurn() async {
        guard activeProviderOption != nil,
              activeTurnModelId != nil else {
            endTurn()
            return
        }
        guard isContinuingTurn == false else { return }

        isContinuingTurn = true
        defer { isContinuingTurn = false }

        while true {
            guard let providerOption = activeProviderOption,
                  let modelId = activeTurnModelId else {
                endTurn()
                return
            }
            guard currentTurnRoundCount < Self.maxToolRoundsPerTurn else {
                errorMessage = "Stopped after \(Self.maxToolRoundsPerTurn) tool rounds to avoid an infinite loop."
                endTurn()
                return
            }

            currentTurnRoundCount += 1
            currentStreamText = ""
            streamingTokens.removeAll()
            isStreaming = true

            let provider = providerOption.makeProvider()
            let toolDefinitions = runtime.toolRegistry.availableDefinitions(for: runtime.toolContext)
            let request = ChatRequest(
                messages: messages,
                model: modelId,
                tools: toolDefinitions.isEmpty ? nil : toolDefinitions
            )

            var partialToolCalls: [Int: PartialToolCall] = [:]
            do {
                for try await chunk in provider.stream(request) {
                    switch chunk.delta {
                    case .text(let text):
                        appendStreamToken(text)
                    case .thinking:
                        continue
                    case let .toolCall(index, id, name, arguments):
                        var partial = partialToolCalls[index] ?? PartialToolCall()
                        partial.merge(id: id, name: name, arguments: arguments)
                        partialToolCalls[index] = partial
                    }
                }
            } catch {
                endTurn()
                errorMessage = error.localizedDescription
                return
            }

            let toolCalls = partialToolCalls
                .sorted { $0.key < $1.key }
                .compactMap { _, partial -> ToolCall? in
                    guard let id = partial.id,
                          let name = partial.name,
                          partial.arguments.isEmpty == false else { return nil }
                    return ToolCall(id: id, name: name, arguments: partial.arguments)
                }

            if toolCalls.isEmpty == false {
                conversationTree.append(ChatMessage.assistant(currentStreamText, toolCalls: toolCalls))
                currentStreamText = ""
                streamingTokens.removeAll()
                isStreaming = false

                let didQueueApproval = await executeToolCalls(toolCalls)
                if didQueueApproval {
                    return
                }
                continue
            }

            finalizeStream()
            endTurn()
            return
        }
    }

    private var activeProviderOption: ProviderOption? {
        let providerId = activeTurnProviderId ?? selectedProviderId
        return providerOptions.first(where: { $0.id == providerId })
    }

    private func beginTurn(providerId: String, modelId: String) {
        activeTurnProviderId = providerId
        activeTurnModelId = modelId
        currentTurnRoundCount = 0
        approvalExecutionsInFlight.removeAll()
        currentStreamText = ""
        streamingTokens.removeAll()
        isStreaming = false
    }

    private func endTurn() {
        activeTurnProviderId = nil
        activeTurnModelId = nil
        currentTurnRoundCount = 0
        approvalExecutionsInFlight.removeAll()
        currentStreamText = ""
        streamingTokens.removeAll()
        isStreaming = false
    }

    private func executeToolCalls(_ toolCalls: [ToolCall]) async -> Bool {
        var safeToolCalls: [ToolCall] = []
        var queuedApproval = false

        for toolCall in toolCalls {
            guard let tool = runtime.toolRegistry.tool(named: toolCall.name) else {
                conversationTree.append(.toolResult(toolCallId: toolCall.id, content: "Error: Unknown tool '\(toolCall.name)'"))
                continue
            }

            let riskLevel = type(of: tool).riskLevel
            if riskLevel == .moderate || riskLevel == .dangerous {
                requestApproval(
                    toolName: toolCall.name,
                    toolCallId: toolCall.id,
                    arguments: toolCall.arguments,
                    riskLevel: riskLevel
                )
                queuedApproval = true
            } else {
                safeToolCalls.append(toolCall)
            }
        }

        guard safeToolCalls.isEmpty == false else {
            return queuedApproval
        }

        let orchestrator = ToolOrchestrator()
        await runtime.toolRegistry.registerAll(into: orchestrator)
        do {
            let results = try await orchestrator.execute(calls: safeToolCalls, context: runtime.toolContext)
            for result in results {
                conversationTree.append(.toolResult(toolCallId: result.toolCallId, content: result.content))
            }
        } catch {
            for toolCall in safeToolCalls {
                conversationTree.append(.toolResult(toolCallId: toolCall.id, content: "Error: \(error.localizedDescription)"))
            }
        }

        return queuedApproval
    }

    private func processApproval(id: UUID) async {
        guard let approval = pendingApprovals.first(where: { $0.id == id }) else { return }
        guard let isApproved = approval.isApproved else { return }

        if isApproved {
            guard approvalExecutionsInFlight.contains(id) == false else { return }
            approvalExecutionsInFlight.insert(id)
        }

        let resultContent: String
        if isApproved == false {
            resultContent = "Denied by user"
        } else if let tool = runtime.toolRegistry.tool(named: approval.toolName) {
            resultContent = await executeToolCall(tool, toolCallId: approval.toolCallId, argumentsJSON: approval.arguments)
        } else {
            resultContent = "Error: Unknown tool '\(approval.toolName)'"
        }

        if isApproved {
            approvalExecutionsInFlight.remove(id)
        }
        pendingApprovals.removeAll { $0.id == id }
        conversationTree.append(.toolResult(toolCallId: approval.toolCallId, content: resultContent))

        if pendingApprovals.isEmpty && approvalExecutionsInFlight.isEmpty {
            await continueCurrentTurn()
        }
    }

    private func executeToolCall(_ tool: any AITool, toolCallId: String, argumentsJSON: String) async -> String {
        let arguments = Self.parseArguments(argumentsJSON)
        do {
            let result = try await tool.execute(arguments: arguments, context: runtime.toolContext)
            return result.content
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private static func parseArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private func buildUserContentParts(text: String) -> [ContentPart] {
        var parts: [ContentPart] = [.text(text)]

        for attachment in attachments {
            switch attachment.type {
            case .image:
                let mediaType = Self.mediaType(for: attachment.name)
                parts.append(.imageBase64(data: attachment.data.base64EncodedString(), mediaType: mediaType))
            case .file:
                parts.append(.text("[Attached file: \(attachment.name)]"))
            }
        }

        return parts
    }

    private static func mediaType(for filename: String) -> String {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic", "heif":
            return "image/heic"
        default:
            return "image/png"
        }
    }
}
