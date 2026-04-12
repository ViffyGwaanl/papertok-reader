import Foundation
import PTCore
import PTNetworking

/// User-configurable OpenAI-compatible provider.
///
/// Lets the user point at any OpenAI-wire-format endpoint (LM Studio, Ollama,
/// OpenRouter, Together, Groq, etc.) with a custom base URL, path, API key,
/// and optional custom headers.
public struct CustomProvider: ChatModelProvider {
    public let id: String
    public let displayName: String
    let baseURL: URL
    let endpointPath: String
    let apiKeyKeychainKey: String?
    let overrideAPIKey: String?
    let customHeaders: [String: String]
    let networkClient: NetworkClient
    let availableModels: [String]

    public init(
        id: String = "custom",
        displayName: String = "Custom",
        baseURL: URL,
        endpointPath: String = "/v1/chat/completions",
        apiKeyKeychainKey: String? = "custom_api_key",
        overrideAPIKey: String? = nil,
        customHeaders: [String: String] = [:],
        availableModels: [String] = [],
        networkClient: NetworkClient = NetworkClient()
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.endpointPath = endpointPath
        self.apiKeyKeychainKey = apiKeyKeychainKey
        self.overrideAPIKey = overrideAPIKey
        self.customHeaders = customHeaders
        self.availableModels = availableModels
        self.networkClient = networkClient
    }

    public var supportedCapabilities: Set<ModelCapability> {
        [.chat, .vision, .toolCalling, .streaming]
    }

    // MARK: - complete

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        let headers = try buildHeaders()
        let openai = OpenAIProvider(overrideAPIKey: "_custom_placeholder")
        let body = openai.buildRequestBody(request: request, stream: false)

        let endpoint = Endpoint(
            method: .post,
            baseURL: baseURL,
            path: endpointPath,
            headers: headers,
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
            calls.map { ToolCall(id: $0.id, name: $0.function.name, arguments: $0.function.arguments) }
        }
        let message = ChatMessage(
            role: .assistant,
            content: [.text(choice.message.content ?? "")],
            toolCalls: toolCalls
        )
        let usage = oaiResponse.usage.map {
            TokenUsage(promptTokens: $0.promptTokens, completionTokens: $0.completionTokens, totalTokens: $0.totalTokens)
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
                    let headers = try buildHeaders()
                    let openai = OpenAIProvider(overrideAPIKey: "_custom_placeholder")
                    let body = openai.buildRequestBody(request: request, stream: true)

                    let endpoint = Endpoint(
                        method: .post,
                        baseURL: baseURL,
                        path: endpointPath,
                        headers: headers,
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

                        let usage = streamResponse.usage.map {
                            TokenUsage(promptTokens: $0.promptTokens, completionTokens: $0.completionTokens, totalTokens: $0.totalTokens)
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

    private func buildHeaders() throws -> [String: String] {
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let apiKey = try resolveAPIKey() {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        for (k, v) in customHeaders {
            headers[k] = v
        }
        return headers
    }

    private func resolveAPIKey() throws -> String? {
        if let key = overrideAPIKey { return key }
        guard let keychainKey = apiKeyKeychainKey else { return nil }
        do {
            return try KeychainService.load(key: keychainKey)
        } catch {
            throw ProviderError.authenticationFailed("Keychain access failed for '\(keychainKey)': \(error.localizedDescription)")
        }
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
