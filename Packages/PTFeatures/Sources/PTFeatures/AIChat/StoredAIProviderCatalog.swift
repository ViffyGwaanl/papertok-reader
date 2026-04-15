import Foundation
import PTCore
import PTAIServices

public enum CustomProviderStore {
    public static let defaultsKey = "ai_custom_providers"

    public static func load(defaults: UserDefaults = AppConfig.groupDefaults) -> [CustomProviderEntry] {
        guard let data = defaults.data(forKey: defaultsKey),
              let entries = try? JSONDecoder().decode([CustomProviderEntry].self, from: data) else {
            return []
        }
        return entries
    }

    public static func save(_ entries: [CustomProviderEntry], defaults: UserDefaults = AppConfig.groupDefaults) {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}

public struct StoredAIProviderCatalog {
    public static let configurationDidChangeNotification = Notification.Name("StoredAIProviderCatalog.configurationDidChange")

    public struct Selection: Sendable, Equatable {
        public let providerId: String
        public let modelId: String
    }

    public struct Snapshot {
        public let runtime: AIChatViewModel.Runtime
        public let selection: Selection
    }

    public struct ResolvedProvider {
        public let providerId: String
        public let modelId: String
        public let provider: any ChatModelProvider
    }

    private struct Descriptor {
        let id: String
        let displayName: String
        let models: [AIChatViewModel.ModelOption]
        let makeProvider: @Sendable () -> any ChatModelProvider

        var providerOption: AIChatViewModel.ProviderOption {
            .init(
                id: id,
                displayName: displayName,
                models: models,
                makeProvider: makeProvider
            )
        }
    }

    private struct UnavailableChatModelProvider: ChatModelProvider {
        let id: String
        let displayName: String
        let supportedCapabilities: Set<ModelCapability>
        let error: Error

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            throw error
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    private struct CapabilityScopedChatModelProvider: ChatModelProvider {
        let base: any ChatModelProvider
        let supportedCapabilities: Set<ModelCapability>

        var id: String { base.id }
        var displayName: String { base.displayName }

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            try await base.complete(request)
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            base.stream(request)
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppConfig.groupDefaults) {
        self.defaults = defaults
    }

    public static func postConfigurationDidChange() {
        NotificationCenter.default.post(name: configurationDidChangeNotification, object: nil)
    }

    public func snapshot(
        toolRegistry: ToolRegistry = .default,
        toolContext: ToolContext = ToolContext()
    ) -> Snapshot {
        let descriptors = providerDescriptors()
        let selection = resolvedSelection(from: descriptors)
        let runtime = AIChatViewModel.Runtime(
            providers: descriptors.map(\.providerOption),
            toolRegistry: toolRegistry,
            toolContext: toolContext
        )
        return Snapshot(runtime: runtime, selection: selection)
    }

    public func resolveCurrentProvider() -> ResolvedProvider {
        let descriptors = providerDescriptors()
        let selection = resolvedSelection(from: descriptors)
        let descriptor = descriptors.first(where: { $0.id == selection.providerId }) ?? descriptors[0]
        let kind = supportedProvider(for: descriptor.id)
        let capabilities: Set<ModelCapability> = {
            var capabilities: Set<ModelCapability> = [.chat, .streaming]
            if kind != .custom {
                capabilities.insert(.toolCalling)
            }
            if supportsThinking(kind: kind, modelId: selection.modelId) {
                capabilities.insert(.thinking)
            }
            if supportsVision(kind: kind, modelId: selection.modelId) {
                capabilities.insert(.vision)
            }
            return capabilities
        }()
        let baseProvider = descriptor.makeProvider()
        return ResolvedProvider(
            providerId: selection.providerId,
            modelId: selection.modelId,
            provider: baseProvider.supportedCapabilities == capabilities
                ? baseProvider
                : CapabilityScopedChatModelProvider(
                    base: baseProvider,
                    supportedCapabilities: capabilities
                )
        )
    }

    private func providerDescriptors() -> [Descriptor] {
        var descriptors = builtInDescriptors()
        descriptors.append(contentsOf: customDescriptors())

        let preferredId = preferredProviderId
        return descriptors.sorted { lhs, rhs in
            if lhs.id == preferredId { return true }
            if rhs.id == preferredId { return false }
            if lhs.id == "custom", rhs.id != "custom" { return false }
            if rhs.id == "custom", lhs.id != "custom" { return true }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func builtInDescriptors() -> [Descriptor] {
        let kinds: [SupportedProvider] = [.openai, .anthropic, .gemini, .azure, .volcengine]
        return kinds.map { kind in
            descriptor(
                id: kind.rawValue,
                displayName: ProviderFactory.displayName(for: kind),
                kind: kind
            )
        }
    }

    private func customDescriptors() -> [Descriptor] {
        CustomProviderStore.load(defaults: defaults).map { entry in
            descriptor(
                id: entry.id,
                displayName: entry.displayName,
                kind: .custom,
                customBaseURL: normalized(entry.baseURL)
            )
        }
    }

    private func descriptor(
        id: String,
        displayName: String,
        kind: SupportedProvider,
        customBaseURL: String? = nil
    ) -> Descriptor {
        let models = modelOptions(for: kind, storageId: id)
        let capabilities = supportedCapabilities(for: kind, models: models.map(\.id))
        let config = providerConfig(for: kind, storageId: id, customBaseURL: customBaseURL, models: models.map(\.id))

        return Descriptor(
            id: id,
            displayName: displayName,
            models: models,
            makeProvider: {
                do {
                    return try ProviderFactory.makeProvider(kind: kind, config: config)
                } catch {
                    return UnavailableChatModelProvider(
                        id: id,
                        displayName: displayName,
                        supportedCapabilities: capabilities,
                        error: error
                    )
                }
            }
        )
    }

    private func resolvedSelection(from descriptors: [Descriptor]) -> Selection {
        if let preferred = descriptors.first(where: { $0.id == preferredProviderId }) {
            let modelId = resolvedModelId(for: preferred)
            return Selection(providerId: preferred.id, modelId: modelId)
        }

        let first = descriptors.first ?? fallbackDescriptor()
        return Selection(
            providerId: first.id,
            modelId: first.models.first?.id ?? fallbackModelId(for: .openai)
        )
    }

    private func fallbackDescriptor() -> Descriptor {
        descriptor(
            id: SupportedProvider.openai.rawValue,
            displayName: ProviderFactory.displayName(for: .openai),
            kind: .openai
        )
    }

    private var preferredProviderId: String {
        normalized(defaults.string(forKey: AppConfig.Keys.aiProviderID))
            ?? AppConfig.Defaults.defaultAIProviderID
    }

    private func resolvedModelId(for descriptor: Descriptor) -> String {
        if let explicit = preferredModelId(for: descriptor.id),
           descriptor.models.contains(where: { $0.id == explicit }) {
            return explicit
        }
        return descriptor.models.first?.id ?? fallbackModelId(for: supportedProvider(for: descriptor.id))
    }

    private func preferredModelId(for storageId: String) -> String? {
        if let stored = normalized(defaults.string(forKey: "ai_model_for_\(storageId)")) {
            return stored
        }
        if storageId == preferredProviderId {
            return normalized(defaults.string(forKey: AppConfig.Keys.aiModelID))
        }
        return nil
    }

    private func modelOptions(for kind: SupportedProvider, storageId: String) -> [AIChatViewModel.ModelOption] {
        let resolvedIds = resolvedModelIds(for: kind, storageId: storageId)
        return resolvedIds.map { modelId in
            AIChatViewModel.ModelOption(
                id: modelId,
                displayName: modelId,
                supportsThinking: supportsThinking(kind: kind, modelId: modelId),
                supportsVision: supportsVision(kind: kind, modelId: modelId)
            )
        }
    }

    private func resolvedModelIds(for kind: SupportedProvider, storageId: String) -> [String] {
        var ids: [String] = []

        if let preferred = preferredModelId(for: storageId) {
            ids.append(preferred)
        }

        for model in ProviderFactory.defaultModels(for: kind) where ids.contains(model) == false {
            ids.append(model)
        }

        if ids.isEmpty {
            ids.append(fallbackModelId(for: kind))
        }

        return ids
    }

    private func providerConfig(
        for kind: SupportedProvider,
        storageId: String,
        customBaseURL: String?,
        models: [String]
    ) -> ProviderConfig {
        let baseURLString = normalized(defaults.string(forKey: "ai_base_url_\(storageId)")) ?? customBaseURL
        let deployment = normalized(defaults.string(forKey: "ai_azure_deployment_\(storageId)"))
        let apiVersion = normalized(defaults.string(forKey: "ai_azure_api_version_\(storageId)"))
        let headers = parseCustomHeaders(defaults.string(forKey: "ai_custom_headers_\(storageId)"))

        return ProviderConfig(
            apiKey: nil,
            baseURL: baseURLString.flatMap(URL.init(string:)),
            customHeaders: headers,
            deploymentName: deployment,
            apiVersion: apiVersion,
            availableModels: models,
            includeThoughts: includeThoughts(for: kind, storageId: storageId),
            geminiSafetyPreset: geminiSafetyPreset(storageId: storageId),
            keyResolver: { APIKeyStore.nextEnabledSecret(providerId: storageId) }
        )
    }

    private func includeThoughts(for kind: SupportedProvider, storageId: String) -> Bool {
        guard kind == .gemini else { return false }
        let key = "ai_include_thoughts_\(storageId)"
        guard defaults.object(forKey: key) != nil else { return false }
        return defaults.bool(forKey: key)
    }

    private func geminiSafetyPreset(storageId: String) -> GeminiSafetyPreset {
        GeminiSafetyPreset(
            rawValue: defaults.string(forKey: "ai_safety_\(storageId)") ?? ""
        ) ?? .default
    }

    private func parseCustomHeaders(_ rawValue: String?) -> [String: String] {
        guard let rawValue = normalized(rawValue) else { return [:] }

        var headers: [String: String] = [:]
        for line in rawValue.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count == 2, parts[0].isEmpty == false, parts[1].isEmpty == false {
                headers[parts[0]] = parts[1]
            }
        }
        return headers
    }

    private func supportedCapabilities(for kind: SupportedProvider, models: [String]) -> Set<ModelCapability> {
        var capabilities: Set<ModelCapability> = [.chat, .streaming]
        if kind != .custom {
            capabilities.insert(.toolCalling)
        }
        if models.contains(where: { supportsThinking(kind: kind, modelId: $0) }) {
            capabilities.insert(.thinking)
        }
        if models.contains(where: { supportsVision(kind: kind, modelId: $0) }) {
            capabilities.insert(.vision)
        }
        return capabilities
    }

    private func supportsThinking(kind: SupportedProvider, modelId: String) -> Bool {
        let normalizedModelId = modelId.lowercased()
        switch kind {
        case .anthropic:
            return true
        case .openai:
            return normalizedModelId.hasPrefix("o")
                || normalizedModelId.hasPrefix("gpt-5")
                || normalizedModelId.contains("reason")
        case .gemini:
            return normalizedModelId.contains("thinking")
                || normalizedModelId.hasPrefix("gemini-2.5")
                || normalizedModelId.hasPrefix("gemini-3")
        case .azure, .volcengine, .custom:
            return false
        }
    }

    private func supportsVision(kind: SupportedProvider, modelId: String) -> Bool {
        switch kind {
        case .openai, .anthropic, .gemini:
            return !modelId.lowercased().contains("text-only")
        case .azure:
            return modelId.lowercased().contains("vision")
                || modelId.lowercased().contains("gpt-4")
                || modelId.lowercased().contains("gpt-4o")
        case .volcengine, .custom:
            return false
        }
    }

    private func supportedProvider(for id: String) -> SupportedProvider {
        SupportedProvider(rawValue: id) ?? .custom
    }

    private func fallbackModelId(for kind: SupportedProvider) -> String {
        if let first = ProviderFactory.defaultModels(for: kind).first {
            return first
        }

        switch kind {
        case .anthropic:
            return AppConfig.Defaults.defaultAnthropicModelID
        case .gemini:
            return "gemini-2.0-flash-exp"
        case .volcengine:
            return "doubao-pro-32k"
        case .azure, .custom, .openai:
            return AppConfig.Defaults.defaultOpenAIModelID
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
