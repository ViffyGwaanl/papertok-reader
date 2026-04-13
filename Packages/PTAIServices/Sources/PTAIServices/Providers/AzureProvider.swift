import Foundation
import PTCore
import PTNetworking

/// Azure OpenAI provider.
///
/// Wire format is identical to OpenAI but URL and auth differ:
/// - Base URL: `https://{resource}.openai.azure.com`
/// - Path: `/openai/deployments/{deployment}/chat/completions`
/// - Query: `api-version={apiVersion}`
/// - Header: `api-key: {key}` (not `Authorization: Bearer`)
public struct AzureProvider: ChatModelProvider {
    public let id: String
    public let displayName: String

    /// Resource base URL, e.g. `https://myresource.openai.azure.com`.
    let baseURL: URL
    /// Deployment name (this maps to the model in Azure OpenAI).
    let deploymentName: String
    let apiVersion: String
    let apiKeyKeychainKey: String
    let overrideAPIKey: String?
    let keyResolver: (@Sendable () -> String?)?
    let networkClient: NetworkClient

    public init(
        id: String = "azure",
        displayName: String = "Azure OpenAI",
        baseURL: URL,
        deploymentName: String,
        apiVersion: String = "2024-02-15-preview",
        apiKeyKeychainKey: String = "azure_openai_api_key",
        overrideAPIKey: String? = nil,
        keyResolver: (@Sendable () -> String?)? = nil,
        networkClient: NetworkClient = NetworkClient()
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.deploymentName = deploymentName
        self.apiVersion = apiVersion
        self.apiKeyKeychainKey = apiKeyKeychainKey
        self.overrideAPIKey = overrideAPIKey
        self.keyResolver = keyResolver
        self.networkClient = networkClient
    }

    public var supportedCapabilities: Set<ModelCapability> {
        [.chat, .vision, .toolCalling, .streaming]
    }

    // MARK: - complete

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        let apiKey = try resolveAPIKey()
        // Delegate request body construction to the shared OpenAI builder.
        let openai = OpenAIProvider(overrideAPIKey: "_azure_placeholder")
        let body = openai.buildRequestBody(request: request, stream: false)

        let endpoint = Endpoint(
            method: .post,
            baseURL: baseURL,
            path: "/openai/deployments/\(deploymentName)/chat/completions",
            headers: [
                "api-key": apiKey,
                "Content-Type": "application/json",
            ],
            queryItems: [URLQueryItem(name: "api-version", value: apiVersion)],
            body: body,
            timeout: 120
        )

        let data: Data
        do {
            data = try await networkClient.requestRaw(endpoint)
        } catch let error as NetworkError {
            throw mapNetworkError(error)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let oaiResponse = try decoder.decode(OAIResponse.self, from: data)

        guard let choice = oaiResponse.choices.first else {
            throw ProviderError.serverError(statusCode: 200, message: "No choices in response")
        }

        let toolCalls: [ToolCall]? = choice.message.toolCalls.map { calls in
            calls.map { tc in
                ToolCall(id: tc.id, name: tc.function.name, arguments: tc.function.arguments)
            }
        }
        let message = ChatMessage(
            role: .assistant,
            content: [.text(choice.message.content ?? "")],
            toolCalls: toolCalls
        )

        let usage = oaiResponse.usage.map { u in
            TokenUsage(promptTokens: u.promptTokens, completionTokens: u.completionTokens, totalTokens: u.totalTokens)
        }

        let finishReason: FinishReason = {
            switch choice.finishReason {
            case "tool_calls": return .toolCalls
            case "length": return .lengthLimit
            case "content_filter": return .contentFilter
            default: return .stop
            }
        }()

        return ChatResponse(message: message, usage: usage, finishReason: finishReason)
    }

    // MARK: - stream

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiKey = try resolveAPIKey()
                    let openai = OpenAIProvider(overrideAPIKey: "_azure_placeholder")
                    let body = openai.buildRequestBody(request: request, stream: true)

                    let endpoint = Endpoint(
                        method: .post,
                        baseURL: baseURL,
                        path: "/openai/deployments/\(deploymentName)/chat/completions",
                        headers: [
                            "api-key": apiKey,
                            "Content-Type": "application/json",
                        ],
                        queryItems: [URLQueryItem(name: "api-version", value: apiVersion)],
                        body: body,
                        timeout: 300
                    )

                    let (bytes, _): (URLSession.AsyncBytes, HTTPURLResponse)
                    do {
                        (bytes, _) = try await networkClient.bytes(endpoint)
                    } catch let error as NetworkError {
                        throw mapNetworkError(error)
                    }

                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase

                    for try await event in SSEParser.events(from: bytes) {
                        if event.isDone { break }
                        guard let data = event.data.data(using: .utf8) else { continue }
                        let streamResponse: OAIStreamResponse
                        do {
                            streamResponse = try decoder.decode(OAIStreamResponse.self, from: data)
                        } catch {
                            continue
                        }

                        let usage = streamResponse.usage.map { u in
                            TokenUsage(promptTokens: u.promptTokens, completionTokens: u.completionTokens, totalTokens: u.totalTokens)
                        }

                        for choice in streamResponse.choices {
                            let finishReason: FinishReason? = {
                                switch choice.finishReason {
                                case "stop": return .stop
                                case "tool_calls": return .toolCalls
                                case "length": return .lengthLimit
                                case "content_filter": return .contentFilter
                                default: return nil
                                }
                            }()

                            let delta = choice.delta
                            if let toolCalls = delta.toolCalls {
                                for toolCall in toolCalls {
                                    continuation.yield(ChatStreamChunk(
                                        delta: .toolCall(
                                            index: toolCall.index,
                                            id: toolCall.id,
                                            name: toolCall.function?.name,
                                            arguments: toolCall.function?.arguments
                                        ),
                                        finishReason: finishReason,
                                        usage: usage
                                    ))
                                }
                            } else if let text = delta.content, !text.isEmpty {
                                continuation.yield(ChatStreamChunk(delta: .text(text), finishReason: finishReason, usage: usage))
                            } else if finishReason != nil || usage != nil {
                                continuation.yield(ChatStreamChunk(delta: .text(""), finishReason: finishReason, usage: usage))
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    private func resolveAPIKey() throws -> String {
        if let resolver = keyResolver, let key = resolver(), !key.isEmpty {
            return key
        }
        if let key = overrideAPIKey, !key.isEmpty { return key }
        do {
            if let key = try KeychainService.load(key: apiKeyKeychainKey) {
                return key
            }
        } catch {
            throw ProviderError.authenticationFailed("Keychain access failed for '\(apiKeyKeychainKey)': \(error.localizedDescription)")
        }
        throw ProviderError.authenticationFailed("No API key found for key '\(apiKeyKeychainKey)'")
    }

    private func mapNetworkError(_ error: NetworkError) -> Error {
        switch error {
        case .httpError(let statusCode, let data):
            let message = data.flatMap { String(data: $0, encoding: .utf8) }
            switch statusCode {
            case 401: return ProviderError.authenticationFailed(message ?? "Unauthorized")
            case 429: return ProviderError.rateLimited(retryAfter: nil)
            default: return ProviderError.serverError(statusCode: statusCode, message: message)
            }
        default:
            return error
        }
    }
}
