import Foundation
import PTCore
import PTNetworking

public enum SupportedProvider: String, CaseIterable, Sendable {
    case openai
    case anthropic
    case gemini
    case azure
    case volcengine
    case custom
}

public enum GeminiSafetyPreset: String, Sendable {
    case `default`
    case strict
    case relaxed
}

public struct ProviderConfig: Sendable {
    public let apiKey: String?
    public let baseURL: URL?
    public let customHeaders: [String: String]
    public let deploymentName: String?
    public let apiVersion: String?
    public let endpointPath: String?
    public let availableModels: [String]
    public let includeThoughts: Bool
    public let geminiSafetyPreset: GeminiSafetyPreset
    public let networkClient: NetworkClient
    /// Optional resolver that returns the next API key to use (for rotation).
    /// If provided and it returns a non-empty string, it takes precedence over
    /// ``apiKey`` and any Keychain fallback.
    public let keyResolver: (@Sendable () -> String?)?

    public init(
        apiKey: String? = nil,
        baseURL: URL? = nil,
        customHeaders: [String: String] = [:],
        deploymentName: String? = nil,
        apiVersion: String? = nil,
        endpointPath: String? = nil,
        availableModels: [String] = [],
        includeThoughts: Bool = false,
        geminiSafetyPreset: GeminiSafetyPreset = .default,
        networkClient: NetworkClient = NetworkClient(),
        keyResolver: (@Sendable () -> String?)? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.customHeaders = customHeaders
        self.deploymentName = deploymentName
        self.apiVersion = apiVersion
        self.endpointPath = endpointPath
        self.availableModels = availableModels
        self.includeThoughts = includeThoughts
        self.geminiSafetyPreset = geminiSafetyPreset
        self.networkClient = networkClient
        self.keyResolver = keyResolver
    }
}

public enum ProviderFactoryError: Error, LocalizedError, Sendable {
    case missingBaseURL(SupportedProvider)
    case missingDeploymentName

    public var errorDescription: String? {
        switch self {
        case .missingBaseURL(let p):
            return AppLocalization.format("errors.ai.provider_base_url_required_format", locale: .autoupdatingCurrent,
                p.rawValue
            )
        case .missingDeploymentName:
            return AppLocalization.string("errors.ai.missing_deployment_name")
        }
    }
}

public enum ProviderFactory {
    public static func makeProvider(
        kind: SupportedProvider,
        config: ProviderConfig = ProviderConfig()
    ) throws -> any ChatModelProvider {
        switch kind {
        case .openai:
            let base = config.baseURL ?? URL(string: "https://api.openai.com")!
            return OpenAIProvider(
                baseURL: base,
                overrideAPIKey: config.apiKey,
                keyResolver: config.keyResolver,
                networkClient: config.networkClient
            )

        case .anthropic:
            let base = config.baseURL ?? URL(string: "https://api.anthropic.com")!
            return AnthropicProvider(
                baseURL: base,
                overrideAPIKey: config.apiKey,
                keyResolver: config.keyResolver,
                networkClient: config.networkClient
            )

        case .gemini:
            let base = config.baseURL ?? URL(string: "https://generativelanguage.googleapis.com")!
            return GeminiProvider(
                baseURL: base,
                overrideAPIKey: config.apiKey,
                includeThoughts: config.includeThoughts,
                safetyPreset: config.geminiSafetyPreset,
                keyResolver: config.keyResolver,
                networkClient: config.networkClient
            )

        case .azure:
            guard let base = config.baseURL else {
                throw ProviderFactoryError.missingBaseURL(.azure)
            }
            guard let deployment = config.deploymentName else {
                throw ProviderFactoryError.missingDeploymentName
            }
            return AzureProvider(
                baseURL: base,
                deploymentName: deployment,
                apiVersion: config.apiVersion ?? "2024-02-15-preview",
                overrideAPIKey: config.apiKey,
                keyResolver: config.keyResolver,
                networkClient: config.networkClient
            )

        case .volcengine:
            let base = config.baseURL ?? URL(string: "https://ark.cn-beijing.volces.com")!
            return VolcengineProvider(
                baseURL: base,
                overrideAPIKey: config.apiKey,
                keyResolver: config.keyResolver,
                networkClient: config.networkClient
            )

        case .custom:
            guard let base = config.baseURL else {
                throw ProviderFactoryError.missingBaseURL(.custom)
            }
            return CustomProvider(
                baseURL: base,
                endpointPath: config.endpointPath ?? "/v1/chat/completions",
                overrideAPIKey: config.apiKey,
                keyResolver: config.keyResolver,
                customHeaders: config.customHeaders,
                availableModels: config.availableModels,
                networkClient: config.networkClient
            )
        }
    }

    public static func defaultModels(for kind: SupportedProvider) -> [String] {
        switch kind {
        case .openai:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o1-mini", "o1-preview"]
        case .anthropic:
            return ["claude-sonnet-4-20250514", "claude-opus-4-20250514", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"]
        case .gemini:
            return ["gemini-2.0-flash-exp", "gemini-1.5-pro", "gemini-1.5-flash"]
        case .azure:
            return []
        case .volcengine:
            return ["doubao-pro-32k", "doubao-pro-128k", "doubao-lite-32k"]
        case .custom:
            return []
        }
    }

    public static func displayName(for kind: SupportedProvider) -> String {
        switch kind {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .azure: return "Azure OpenAI"
        case .volcengine: return "Volcengine (Doubao)"
        case .custom: return AppLocalization.string("settings.custom_provider")
        }
    }
}
