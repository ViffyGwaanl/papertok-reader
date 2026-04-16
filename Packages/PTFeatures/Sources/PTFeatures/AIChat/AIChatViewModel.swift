import Foundation
import Observation
import PTCore
import PTAIServices

@MainActor @Observable
public final class AIChatViewModel {
    public struct RuntimeSelection: Sendable, Equatable {
        public let providerId: String
        public let modelId: String

        public init(providerId: String, modelId: String) {
            self.providerId = providerId
            self.modelId = modelId
        }
    }

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
                    makeProvider: {
                        OpenAIProvider(
                            keyResolver: { APIKeyStore.nextEnabledSecret(providerId: "openai") }
                        )
                    }
                ),
                ProviderOption(
                    id: "anthropic",
                    displayName: "Anthropic",
                    models: [
                        ModelOption(id: "claude-sonnet-4-20250514", displayName: "Claude Sonnet 4", supportsThinking: true, supportsVision: true)
                    ],
                    makeProvider: {
                        AnthropicProvider(
                            keyResolver: { APIKeyStore.nextEnabledSecret(providerId: "anthropic") }
                        )
                    }
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

    /// Generation settings tunable via ChatSettingsSheet.
    public struct ChatGenerationSettings: Sendable, Equatable {
        public var temperature: Double
        public var maxTokens: Int
        public var topP: Double
        public var presencePenalty: Double
        public var frequencyPenalty: Double
        public var stopSequences: [String]
        public var systemPrompt: String
        public var perConversation: Bool
        public var thinkingBudgetTokens: Int?

        public init(
            temperature: Double,
            maxTokens: Int,
            topP: Double,
            presencePenalty: Double,
            frequencyPenalty: Double,
            stopSequences: [String],
            systemPrompt: String,
            perConversation: Bool,
            thinkingBudgetTokens: Int? = nil
        ) {
            self.temperature = temperature
            self.maxTokens = maxTokens
            self.topP = topP
            self.presencePenalty = presencePenalty
            self.frequencyPenalty = frequencyPenalty
            self.stopSequences = stopSequences
            self.systemPrompt = systemPrompt
            self.perConversation = perConversation
            self.thinkingBudgetTokens = thinkingBudgetTokens
        }

        public static let `default` = ChatGenerationSettings(
            temperature: 0.7,
            maxTokens: 4096,
            topP: 1.0,
            presencePenalty: 0.0,
            frequencyPenalty: 0.0,
            stopSequences: [],
            systemPrompt: aiChatLocalizedCatalogString("ai.chat.system_prompt_default"),
            perConversation: false,
            thinkingBudgetTokens: nil
        )
    }

    public var settings: ChatGenerationSettings = .default

    /// Non-blocking informational message (e.g. budget truncation toast).
    public var infoMessage: String?

    private let maxTokensStrategy: MaxTokensStrategy
    private let promptBudgeter: PromptBudgeter
    private let compressor: ConversationCompressor?
    private let titleService: AutoTitleService?
    private let usageTracker: UsageTracker?

    /// Per-message transient status used for delivery indicators.
    public enum MessageStatus: Sendable, Equatable { case sending, sent, failed }
    public var messageStatuses: [String: MessageStatus] = [:]

    public var conversationTree: ConversationTree
    public var isStreaming: Bool = false
    public var currentStreamText: String = ""
    public var errorMessage: String?
    public private(set) var runtime: Runtime
    private let defaults: UserDefaults
    private var activeTurnProviderId: String?
    private var activeTurnModelId: String?
    private var isContinuingTurn = false
    private var currentTurnRoundCount = 0
    private var approvalExecutionsInFlight: Set<UUID> = []
    private var pendingRuntimeUpdate: (runtime: Runtime, selection: RuntimeSelection)?
    private var streamingTask: Task<Void, Never>?
    private static let maxToolRoundsPerTurn = 8
    /// Minimum interval between streaming-token flushes to coalesce SwiftUI re-renders.
    private static let streamingFlushInterval: Duration = .milliseconds(30)

    /// Public read-only accessor for tests to verify in-flight streaming Task lifecycle.
    public var isStreamingTaskActive: Bool { streamingTask != nil }

    /// Persistence service for saving/loading conversations (optional).
    public var persistenceService: ConversationPersistenceService?
    /// Identifier of the current conversation for persistence.
    public var conversationId: String?
    /// Title of the current conversation (derived from first user message).
    public var conversationTitle: String = aiChatLocalizedCatalogString("ai.new_conversation")
    /// Book identifier of the reader host that is currently driving the chat, if any.
    /// Set by the reader entry points in W2.1b; stamped into freshly-created conversations only.
    public var currentBookId: String? = nil

    public init(
        systemPrompt: String? = nil,
        runtime: Runtime = .default,
        persistenceService: ConversationPersistenceService? = nil,
        defaults: UserDefaults = AppConfig.groupDefaults,
        maxTokensStrategy: MaxTokensStrategy = MaxTokensStrategy(),
        promptBudgeter: PromptBudgeter? = nil,
        compressor: ConversationCompressor? = nil,
        titleService: AutoTitleService? = nil,
        usageTracker: UsageTracker? = nil
    ) {
        self.defaults = defaults
        self.maxTokensStrategy = maxTokensStrategy
        self.promptBudgeter = promptBudgeter ?? PromptBudgeter(
            truncationMarker: aiChatLocalizedCatalogString("reader.context.truncated_marker")
        )
        self.compressor = compressor
        self.titleService = titleService
        self.usageTracker = usageTracker
        let initialProviderId = runtime.providers.first?.id ?? ""
        let initialPreferences = AIChatRuntimePreferences.load(
            defaults: defaults,
            providerId: initialProviderId
        )
        var initialSettings = initialPreferences.generationSettings
        if let systemPrompt {
            initialSettings.systemPrompt = systemPrompt
        }
        self.settings = initialSettings
        self.thinkingLevel = initialPreferences.defaultThinkingLevel
        self.conversationTree = ConversationTree(
            systemPrompt: initialSettings.systemPrompt
        )
        self.runtime = runtime
        self.persistenceService = persistenceService
        self.selectedProviderId = initialProviderId
        self.selectedModelId = runtime.providers.first?.models.first?.id ?? ""
    }

    /// Messages in the active conversation branch.
    public var messages: [ChatMessage] {
        conversationTree.activeMessages()
    }

    public var providerOptions: [ProviderOption] {
        runtime.providers
    }

    public func makeTranslationService() -> AITranslationService? {
        guard let providerOption = providerOptions.first(where: { $0.id == selectedProviderId }),
              providerOption.models.contains(where: { $0.id == selectedModelId }) else {
            return nil
        }
        return AITranslationService(
            provider: providerOption.makeProvider(),
            model: selectedModelId
        )
    }

    /// Send a user message and stream the provider response into the active branch.
    @discardableResult
    public func sendMessage(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        guard !isStreaming else { return false }
        guard let providerOption = providerOptions.first(where: { $0.id == selectedProviderId }) else {
            errorMessage = aiChatLocalizedCatalogString("errors.ai.selected_provider_unavailable")
            return false
        }
        guard providerOption.models.contains(where: { $0.id == selectedModelId }) else {
            errorMessage = aiChatLocalizedCatalogString("errors.ai.selected_model_unavailable")
            return false
        }
        guard pendingApprovals.isEmpty else {
            errorMessage = aiChatLocalizedCatalogString("errors.ai.pending_tool_approvals")
            return false
        }

        let signpostID = PerformanceSignposts.beginChatSend()
        errorMessage = nil
        beginTurn(providerId: providerOption.id, modelId: selectedModelId)
        conversationTree.append(ChatMessage(role: .user, content: buildUserContentParts(text: trimmed)))
        clearAttachments()
        await continueCurrentTurn()
        PerformanceSignposts.endChatSend(signpostID)
        return errorMessage == nil
    }

    /// Add an assistant response (used after streaming completes).
    public func addAssistantMessage(_ text: String) {
        conversationTree.append(.assistant(text))
    }

    /// Clear conversation and start fresh.
    public func clearConversation(systemPrompt: String? = nil) {
        let resolvedSystemPrompt = systemPrompt ?? settings.systemPrompt
        conversationTree = ConversationTree(
            systemPrompt: resolvedSystemPrompt
        )
        settings.systemPrompt = resolvedSystemPrompt
        conversationId = nil
        conversationTitle = aiChatLocalizedCatalogString("ai.new_conversation")
        endTurn()
        errorMessage = nil
        pendingApprovals.removeAll()
        attachments.removeAll()
    }

    // MARK: - Conversation Persistence

    /// Save the current conversation to disk.
    public func saveConversation() {
        guard let service = persistenceService else { return }
        let id = conversationId ?? UUID().uuidString
        if conversationId == nil { conversationId = id }

        // Derive title from the first user message if still default
        if conversationTitle == aiChatLocalizedCatalogString("ai.new_conversation") {
            if let firstUserMsg = messages.first(where: { $0.role == .user })?.textContent {
                conversationTitle = String(firstUserMsg.prefix(60))
            }
        }

        let systemPrompt = messages.first(where: { $0.role == .system })?.textContent ?? aiChatLocalizedCatalogString("ai.chat.system_prompt_default")
        let existing = (try? service.load(id: id)) ?? nil
        let persisted = ConversationPersistenceService.PersistedConversation(
            id: id,
            title: conversationTitle,
            systemPrompt: systemPrompt,
            tree: conversationTree,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date(),
            providerId: selectedProviderId,
            modelId: selectedModelId,
            isPinned: existing?.isPinned ?? false,
            bookId: existing?.bookId ?? currentBookId
        )
        try? service.save(persisted)
    }

    /// Load and resume a conversation from disk.
    public func loadConversation(id: String) -> Bool {
        guard isStreaming == false else { return false }
        guard let service = persistenceService,
              let persisted = try? service.load(id: id) else { return false }
        conversationTree = persisted.tree
        conversationId = persisted.id
        conversationTitle = persisted.title
        settings.systemPrompt = persisted.systemPrompt
        if let providerId = persisted.providerId { selectedProviderId = providerId }
        if let modelId = persisted.modelId { selectedModelId = modelId }
        endTurn()
        errorMessage = nil
        pendingApprovals.removeAll()
        attachments.removeAll()
        return true
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

    public var selectedProviderId: String = "" {
        didSet {
            guard oldValue != selectedProviderId else { return }
            syncSelectionAfterProviderChange()
            persistSelection()
        }
    }
    public var selectedModelId: String = "" {
        didSet {
            guard oldValue != selectedModelId else { return }
            persistModelSelection()
        }
    }
    public var thinkingLevel: ThinkingLevel = .off {
        didSet {
            guard oldValue != thinkingLevel else { return }
            AIChatRuntimePreferences.persistThinkingLevel(thinkingLevel, defaults: defaults)
        }
    }

    public var thinkingEnabled: Bool {
        get { thinkingLevel != .off }
        set {
            thinkingLevel = newValue
                ? AIChatRuntimePreferences.defaultThinkingLevel(defaults: defaults, providerId: selectedProviderId)
                : .off
        }
    }

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
        // Auto-save after stream completes
        saveConversation()
        maybeSpawnAutoTitleTask()
        applyPendingRuntimeUpdateIfNeeded()
    }

    /// Fires the auto-title background task after the first assistant turn of a
    /// new conversation completes. No-op when: titleService is unset, conversation
    /// already has a non-default title, or this is not the first assistant turn.
    private func maybeSpawnAutoTitleTask() {
        guard let service = titleService,
              let persistence = persistenceService,
              let id = conversationId else { return }
        let defaultTitle = aiChatLocalizedCatalogString("ai.new_conversation")
        guard conversationTitle == defaultTitle
            || conversationTitle.isEmpty
            || conversationTitle.count <= 60 else { return }
        let nonSystemMessages = messages.filter { $0.role != .system }
        let userCount = nonSystemMessages.filter { $0.role == .user }.count
        let assistantCount = nonSystemMessages.filter { $0.role == .assistant }.count
        guard userCount == 1, assistantCount == 1 else { return }
        // Only fire for conversations whose title was never overridden by user.
        // A manually-renamed "existing" conversation will have a title that does
        // not equal the default and does not match the derived prefix — we skip
        // those by only considering conversations where userCount==1 & assistantCount==1.
        let snapshot = messages
        Task.detached { [service, persistence, id] in
            if let newTitle = await service.generateTitle(from: snapshot, locale: .current) {
                try? persistence.updateTitle(id: id, newTitle)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.conversationId == id {
                        self.conversationTitle = newTitle
                    }
                }
            }
        }
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

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runStreamingLoop()
        }
        streamingTask = task
        await task.value
        if streamingTask == task {
            streamingTask = nil
        }
    }

    private func runStreamingLoop() async {
        while true {
            if Task.isCancelled { return }
            guard let providerOption = activeProviderOption,
                  let modelId = activeTurnModelId else {
                endTurn()
                return
            }
            guard currentTurnRoundCount < Self.maxToolRoundsPerTurn else {
                errorMessage = aiChatLocalizedCatalogFormat(
                    "errors.ai.tool_round_limit_format",
                    Int64(Self.maxToolRoundsPerTurn)
                )
                endTurn()
                return
            }

            currentTurnRoundCount += 1
            currentStreamText = ""
            streamingTokens.removeAll()
            isStreaming = true

            let provider = providerOption.makeProvider()
            let requestPreferences = effectiveRuntimePreferences()
            let toolDefinitions = availableToolDefinitions(enabledToolNames: requestPreferences.enabledToolNames)

            let compressionInput: [ChatMessage]
            if let compressor {
                let compressionResult: ConversationCompressor.Result
                do {
                    compressionResult = try await compressor.compressIfNeeded(messages)
                } catch {
                    compressionResult = ConversationCompressor.Result(
                        messages: messages,
                        didCompress: false,
                        summarizedMessageCount: 0
                    )
                }
                _ = compressionResult.didCompress
                compressionInput = compressionResult.messages
            } else {
                compressionInput = messages
            }
            let budgetResult = promptBudgeter.budget(compressionInput)
            if budgetResult.wasTruncated {
                infoMessage = aiChatLocalizedCatalogString("chat.budget.message_truncated.toast")
            }
            let budgetedMessages = budgetResult.messages
            let modelLimits = ModelContextWindowCatalog.limits(for: modelId)
            let estimatedPromptTokens = estimatePromptTokens(budgetedMessages)
            let userMaxTokens = requestPreferences.generationSettings.maxTokens
            let resolvedMaxTokens = maxTokensStrategy.resolve(
                userOverride: userMaxTokens > 0 ? userMaxTokens : nil,
                modelMaxOutput: modelLimits.maxOutput,
                contextWindow: modelLimits.contextWindow,
                estimatedPromptTokens: estimatedPromptTokens
            )

            let request = ChatRequest(
                messages: budgetedMessages,
                model: modelId,
                temperature: requestPreferences.generationSettings.temperature,
                maxTokens: resolvedMaxTokens,
                topP: requestPreferences.generationSettings.topP,
                presencePenalty: requestPreferences.generationSettings.presencePenalty,
                frequencyPenalty: requestPreferences.generationSettings.frequencyPenalty,
                stopSequences: requestPreferences.generationSettings.stopSequences.isEmpty
                    ? nil
                    : requestPreferences.generationSettings.stopSequences,
                tools: toolDefinitions.isEmpty ? nil : toolDefinitions,
                thinkingLevel: thinkingLevelForCurrentRequest(provider: providerOption),
                thinkingBudgetTokens: requestPreferences.generationSettings.thinkingBudgetTokens,
                responseFormat: requestPreferences.responseFormat
            )

            var partialToolCalls: [Int: PartialToolCall] = [:]
            var pendingText = ""
            var capturedUsage: TokenUsage?
            var lastFlush = ContinuousClock.now
            let clock = ContinuousClock()
            func flushPending() {
                if pendingText.isEmpty == false {
                    appendStreamToken(pendingText)
                    pendingText = ""
                    lastFlush = ContinuousClock.now
                }
            }
            do {
                for try await chunk in provider.stream(request) {
                    if Task.isCancelled {
                        flushPending()
                        return
                    }
                    if let usage = chunk.usage {
                        capturedUsage = usage
                    }
                    switch chunk.delta {
                    case .text(let text):
                        pendingText += text
                        if clock.now - lastFlush >= Self.streamingFlushInterval {
                            flushPending()
                        }
                    case .thinking:
                        continue
                    case let .toolCall(index, id, name, arguments):
                        var partial = partialToolCalls[index] ?? PartialToolCall()
                        partial.merge(id: id, name: name, arguments: arguments)
                        partialToolCalls[index] = partial
                    }
                }
                flushPending()
            } catch is CancellationError {
                flushPending()
                return
            } catch {
                flushPending()
                endTurn()
                if Self.isOfflineError(error) {
                    errorMessage = aiChatLocalizedCatalogString("chat.error.offline")
                } else if error is ProviderError {
                    errorMessage = AppLocalization.userFacingErrorMessage(
                        for: error,
                        fallbackKey: "errors.ai.streaming_interrupted"
                    )
                } else {
                    errorMessage = aiChatLocalizedCatalogString("errors.ai.streaming_interrupted")
                }
                return
            }
            if Task.isCancelled { return }

            // Usage tracking: only after a successful (non-cancelled, non-error) provider call.
            if let tracker = usageTracker, let usage = capturedUsage {
                await tracker.record(
                    modelId: modelId,
                    usage: usage,
                    conversationId: conversationId
                )
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
        applyPendingRuntimeUpdateIfNeeded()
    }

    /// Returns `true` when the error indicates the device is offline.
    nonisolated static func isOfflineError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        // Check wrapped URLErrors (e.g. inside ProviderError or other wrappers)
        if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? URLError {
            return Self.isOfflineError(underlying)
        }
        return false
    }

    private func executeToolCalls(_ toolCalls: [ToolCall]) async -> Bool {
        var safeToolCalls: [ToolCall] = []
        var queuedApproval = false

        for toolCall in toolCalls {
            guard let tool = enabledTool(named: toolCall.name) else {
                conversationTree.append(.toolResult(
                    toolCallId: toolCall.id,
                    content: aiChatLocalizedCatalogFormat(
                        "errors.ai.unknown_tool_format",
                        toolCall.name
                    )
                ))
                continue
            }

            let riskLevel = type(of: tool).riskLevel
            if effectiveRuntimePreferences().approvalPolicy.requiresApproval(for: riskLevel) {
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
                conversationTree.append(
                    .toolResult(
                        toolCallId: result.toolCallId,
                        content: userFacingToolResultContent(for: result)
                    )
                )
            }
        } catch {
            for toolCall in safeToolCalls {
                conversationTree.append(.toolResult(
                    toolCallId: toolCall.id,
                    content: toolFailureContent(detail: AppLocalization.errorDetail(error))
                ))
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
            resultContent = aiChatLocalizedCatalogString("errors.ai.tool_denied")
        } else if let tool = enabledTool(named: approval.toolName) {
            let result = await executeToolCall(tool, toolCallId: approval.toolCallId, argumentsJSON: approval.arguments)
            resultContent = userFacingToolResultContent(for: result)
        } else {
            resultContent = aiChatLocalizedCatalogFormat(
                "errors.ai.unknown_tool_format",
                approval.toolName
            )
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

    private func executeToolCall(_ tool: any AITool, toolCallId: String, argumentsJSON: String) async -> ToolResult {
        let arguments = Self.parseArguments(argumentsJSON)
        do {
            let result = try await tool.execute(arguments: arguments, context: runtime.toolContext)
            return ToolResult(toolCallId: toolCallId, content: result.content, isError: result.isError)
        } catch {
            return ToolResult(
                toolCallId: toolCallId,
                content: AppLocalization.errorDetail(error),
                isError: true
            )
        }
    }

    private func userFacingToolResultContent(for result: ToolResult) -> String {
        guard result.isError else { return result.content }
        return toolFailureContent(detail: result.content)
    }

    private func toolFailureContent(detail: String?) -> String {
        let summary = aiChatLocalizedCatalogString("errors.ai.tool_failed")
        // Tool execution layers still emit raw English strings and machine-oriented
        // JSON payloads. Until we have an explicit "safe to show" contract for tool
        // error details, keep the user-visible bubble summary-only.
        _ = detail
        return summary
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
                parts.append(.text(aiChatLocalizedCatalogFormat("ai.chat.attachment_file_format", attachment.name)))
            }
        }

        return parts
    }

    // MARK: - Message Helpers

    /// Returns the createdAt timestamp for a message in the current tree, if any.
    public func timestamp(for messageId: String) -> Date? {
        conversationTree.nodes.values.first(where: { $0.message.id == messageId })?.createdAt
    }

    /// Cancels current streaming generation.
    public func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        if currentStreamText.isEmpty == false {
            addAssistantMessage(currentStreamText)
        }
        currentStreamText = ""
        streamingTokens.removeAll()
        isStreaming = false
        endTurn()
    }

    /// Regenerate the last assistant message by retrying it.
    ///
    /// The previous branch is preserved as a sibling so the user can navigate
    /// back to it via the per-message branch navigator.
    public func regenerateLastAssistant() async {
        guard isStreaming == false else { return }
        let leafId = conversationTree.activeLeafId()
        guard let leaf = conversationTree.nodes[leafId], leaf.role == .assistant else { return }
        await retry(messageId: leafId)
    }

    /// Edit a user message and generate a new assistant response.
    ///
    /// Creates a new user sibling branch via `editUserMessage`, activates it,
    /// then triggers a fresh assistant generation. Accepts either a
    /// `ChatMessage.id` or a conversation-tree node id.
    public func editAndResend(messageId: String, newText: String) async {
        guard isStreaming == false else { return }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard let nodeId = resolveNodeId(for: messageId) else { return }
        guard conversationTree.editUserMessage(nodeId, newText: trimmed) != nil else { return }
        errorMessage = nil
        beginTurn(providerId: selectedProviderId, modelId: selectedModelId)
        await continueCurrentTurn()
        saveConversation()
    }

    /// Retry an assistant message by creating a new sibling branch.
    ///
    /// The old branch is preserved so the branch navigator can toggle between
    /// variants. Streaming chunks land in the new branch. Accepts either a
    /// `ChatMessage.id` or a conversation-tree node id.
    public func retry(messageId: String) async {
        guard isStreaming == false else { return }
        guard let nodeId = resolveNodeId(for: messageId),
              let target = conversationTree.nodes[nodeId], target.role == .assistant,
              let parentId = target.parentId,
              let parent = conversationTree.nodes[parentId] else { return }
        let preservedChildIds = parent.childIds
        let preservedActiveIndex = parent.activeChildIndex
        // Temporarily detach existing siblings so the active leaf resolves to
        // the parent and the streaming loop appends the fresh response there.
        conversationTree.nodes[parentId]?.childIds = []
        conversationTree.nodes[parentId]?.activeChildIndex = 0
        errorMessage = nil
        beginTurn(providerId: selectedProviderId, modelId: selectedModelId)
        await continueCurrentTurn()
        // After streaming, parent's childIds contains the new branch (one or
        // more nodes from tool-call rounds and the final assistant response).
        // Re-attach the preserved siblings at the front and activate the new
        // branch (which occupies the tail).
        guard var parentNow = conversationTree.nodes[parentId] else { return }
        let newChildIds = parentNow.childIds
        let mergedChildIds = preservedChildIds + newChildIds
        parentNow.childIds = mergedChildIds
        if newChildIds.isEmpty {
            // Streaming failed to produce a new branch; restore original state.
            parentNow.activeChildIndex = preservedActiveIndex
        } else {
            parentNow.activeChildIndex = preservedChildIds.count
        }
        conversationTree.nodes[parentId] = parentNow
        saveConversation()
    }

    /// Switch the active path to the given branch node. Accepts either a
    /// `ChatMessage.id` or a conversation-tree node id.
    public func switchToBranch(_ messageId: String) {
        guard let nodeId = resolveNodeId(for: messageId) else { return }
        conversationTree.switchToBranch(nodeId)
    }

    /// Returns `(index, total)` for the branch navigator, where `index` is the
    /// 1-based position of `messageId` among its parent's children and `total`
    /// is the sibling count. Returns nil when the message has fewer than two
    /// siblings. Accepts either a `ChatMessage.id` or a node id.
    public func branchNavigatorState(for messageId: String) -> (index: Int, total: Int)? {
        guard let nodeId = resolveNodeId(for: messageId) else { return nil }
        let siblings = conversationTree.branchSiblings(of: nodeId)
        guard siblings.count > 1,
              let pos = siblings.firstIndex(of: nodeId) else {
            return nil
        }
        return (index: pos + 1, total: siblings.count)
    }

    /// Returns the branch sibling node id immediately before or after
    /// `messageId` (by `offset`), or nil at the boundary.
    public func siblingNodeId(for messageId: String, offset: Int) -> String? {
        guard let nodeId = resolveNodeId(for: messageId) else { return nil }
        let siblings = conversationTree.branchSiblings(of: nodeId)
        guard let pos = siblings.firstIndex(of: nodeId) else { return nil }
        let next = pos + offset
        guard next >= 0, next < siblings.count else { return nil }
        return siblings[next]
    }

    /// Maps a `ChatMessage.id` to its conversation-tree node id. If the input
    /// is already a node key, it is returned unchanged.
    private func resolveNodeId(for messageId: String) -> String? {
        if conversationTree.nodes[messageId] != nil { return messageId }
        return conversationTree.nodes.first(where: { $0.value.message.id == messageId })?.key
    }

    /// Retry the last failed user message by re-running the turn.
    public func retryLastUserMessage() async {
        guard let lastUser = messages.last(where: { $0.role == .user }),
              let text = lastUser.textContent else { return }
        messageStatuses[lastUser.id] = .sending
        let leafId = conversationTree.activeLeafId()
        if let leaf = conversationTree.nodes[leafId],
           leaf.role == .assistant,
           let parentId = leaf.parentId {
            conversationTree.nodes[parentId]?.childIds.removeAll { $0 == leafId }
            conversationTree.nodes.removeValue(forKey: leafId)
        }
        _ = await sendMessage(text)
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

    public func toggleThinking() {
        thinkingEnabled.toggle()
    }

    public func applyChatSettings(_ newSettings: ChatGenerationSettings) {
        settings = newSettings
        updateConversationSystemPrompt(newSettings.systemPrompt)
        if newSettings.perConversation == false {
            AIChatRuntimePreferences.persist(
                newSettings,
                defaults: defaults,
                providerId: selectedProviderId
            )
        }
    }

    public func updateRuntime(_ runtime: Runtime, selection: RuntimeSelection) {
        if isStreaming || activeTurnProviderId != nil {
            pendingRuntimeUpdate = (runtime, selection)
            return
        }
        applyRuntimeUpdate(runtime, selection: selection)
    }

    private func effectiveRuntimePreferences() -> AIChatRuntimePreferences {
        let stored = AIChatRuntimePreferences.load(
            defaults: defaults,
            providerId: selectedProviderId
        )
        if settings.perConversation {
            return AIChatRuntimePreferences(
                enabledToolNames: stored.enabledToolNames,
                approvalPolicy: stored.approvalPolicy,
                generationSettings: settings,
                defaultThinkingLevel: stored.defaultThinkingLevel,
                responseFormat: stored.responseFormat
            )
        }
        settings = stored.generationSettings
        return stored
    }

    private func availableToolDefinitions(enabledToolNames: Set<String>) -> [ToolDefinition] {
        let definitions = runtime.toolRegistry.availableDefinitions(for: runtime.toolContext)
        guard enabledToolNames.isEmpty == false else { return definitions }
        return definitions.filter { enabledToolNames.contains($0.name) }
    }

    private func enabledTool(named name: String) -> (any AITool)? {
        let enabledToolNames = effectiveRuntimePreferences().enabledToolNames
        guard enabledToolNames.isEmpty || enabledToolNames.contains(name) else {
            return nil
        }
        return runtime.toolRegistry.tool(named: name)
    }

    private func thinkingLevelForCurrentRequest(provider: ProviderOption) -> ThinkingLevel? {
        guard thinkingEnabled else { return nil }
        guard let model = provider.models.first(where: { $0.id == selectedModelId }),
              model.supportsThinking else {
            return nil
        }
        return thinkingLevel == .off ? nil : thinkingLevel
    }

    private func persistSelection() {
        defaults.set(selectedProviderId, forKey: AppConfig.Keys.aiProviderID)
        persistModelSelection()
    }

    private func syncSelectionAfterProviderChange() {
        guard let provider = providerOptions.first(where: { $0.id == selectedProviderId }) else { return }
        if let persistedModelId = persistedModelSelection(for: selectedProviderId),
           provider.models.contains(where: { $0.id == persistedModelId }) {
            if selectedModelId != persistedModelId {
                selectedModelId = persistedModelId
            }
        } else if provider.models.contains(where: { $0.id == selectedModelId }) == false {
            selectedModelId = provider.models.first?.id ?? ""
        }
        reloadPersistedRuntimePreferencesIfNeeded()
    }

    private func persistModelSelection() {
        defaults.set(selectedModelId, forKey: AppConfig.Keys.aiModelID)
        guard selectedProviderId.isEmpty == false,
              selectedModelId.isEmpty == false else {
            return
        }
        defaults.set(selectedModelId, forKey: providerScopedModelDefaultsKey(for: selectedProviderId))
    }

    private func persistedModelSelection(for providerId: String) -> String? {
        if let scopedModelId = normalized(defaults.string(forKey: providerScopedModelDefaultsKey(for: providerId))) {
            return scopedModelId
        }

        let persistedProviderId = normalized(defaults.string(forKey: AppConfig.Keys.aiProviderID))
        if persistedProviderId == providerId {
            return normalized(defaults.string(forKey: AppConfig.Keys.aiModelID))
        }

        return nil
    }

    private func providerScopedModelDefaultsKey(for providerId: String) -> String {
        "ai_model_for_\(providerId)"
    }

    private func updateConversationSystemPrompt(_ systemPrompt: String) {
        guard let rootNode = conversationTree.nodes[conversationTree.rootId] else { return }
        conversationTree.nodes[conversationTree.rootId] = .init(
            id: rootNode.id,
            message: .system(systemPrompt),
            parentId: rootNode.parentId,
            createdAt: rootNode.createdAt
        )
        conversationTree.nodes[conversationTree.rootId]?.childIds = rootNode.childIds
        conversationTree.nodes[conversationTree.rootId]?.activeChildIndex = rootNode.activeChildIndex
    }

    private func reloadPersistedRuntimePreferencesIfNeeded() {
        guard settings.perConversation == false else { return }
        let stored = AIChatRuntimePreferences.load(defaults: defaults, providerId: selectedProviderId)
        settings = stored.generationSettings
        thinkingLevel = stored.defaultThinkingLevel
    }

    private func applyRuntimeUpdate(_ runtime: Runtime, selection: RuntimeSelection) {
        self.runtime = runtime

        let resolvedProviderId: String
        if runtime.providers.contains(where: { $0.id == selection.providerId }) {
            resolvedProviderId = selection.providerId
        } else {
            resolvedProviderId = runtime.providers.first?.id ?? ""
        }

        let resolvedModelId: String
        if let provider = runtime.providers.first(where: { $0.id == resolvedProviderId }),
           provider.models.contains(where: { $0.id == selection.modelId }) {
            resolvedModelId = selection.modelId
        } else {
            resolvedModelId = runtime.providers
                .first(where: { $0.id == resolvedProviderId })?
                .models
                .first?
                .id ?? ""
        }

        selectedProviderId = resolvedProviderId
        selectedModelId = resolvedModelId
        reloadPersistedRuntimePreferencesIfNeeded()
    }

    /// Rough token estimator: per-message CJK runes count as 1 token each,
    /// non-CJK characters collapse at ~4 chars/token. Per-message overhead of
    /// 24 tokens accounts for role framing. Mirrors the Flutter reference.
    private func estimatePromptTokens(_ messages: [ChatMessage]) -> Int {
        var total = 0
        for message in messages {
            total += 24
            for part in message.content {
                if case .text(let text) = part {
                    total += Self.estimateTextTokens(text)
                }
            }
        }
        return total
    }

    private static func estimateTextTokens(_ text: String) -> Int {
        if text.isEmpty { return 0 }
        var cjk = 0
        var nonCjk = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (v >= 0x4E00 && v <= 0x9FFF) ||
               (v >= 0x3400 && v <= 0x4DBF) ||
               (v >= 0x20000 && v <= 0x2A6DF) {
                cjk += 1
            } else {
                nonCjk += 1
            }
        }
        return cjk + Int((Double(nonCjk) / 4.0).rounded(.up))
    }

    private func applyPendingRuntimeUpdateIfNeeded() {
        guard let pendingRuntimeUpdate,
              isStreaming == false,
              activeTurnProviderId == nil else { return }
        self.pendingRuntimeUpdate = nil
        applyRuntimeUpdate(pendingRuntimeUpdate.runtime, selection: pendingRuntimeUpdate.selection)
    }
}

private func aiChatLocalizedCatalogString(_ key: String, locale: Locale = .autoupdatingCurrent) -> String {
    String(localized: String.LocalizationValue(key), bundle: aiChatLocalizedCatalogBundle(), locale: locale)
}

private func aiChatLocalizedCatalogFormat(_ key: String, locale: Locale = .autoupdatingCurrent, _ arguments: CVarArg...) -> String {
    String(format: aiChatLocalizedCatalogString(key, locale: locale), locale: locale, arguments: arguments)
}

private func aiChatLocalizedCatalogBundle() -> Bundle {
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

private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
