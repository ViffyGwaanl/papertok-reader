import Foundation
import PTCore
import PTNetworking

// MARK: - Internal JSON model types

struct OAIRequestBody: Encodable, Sendable {
    let model: String
    let messages: [OAIMessage]
    let temperature: Double?
    let maxTokens: Int?
    let tools: [OAITool]?
    let responseFormat: OAIResponseFormat?
    let stream: Bool
    let streamOptions: OAIStreamOptions?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, tools, stream
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
        case streamOptions = "stream_options"
    }
}

struct OAIStreamOptions: Encodable, Sendable {
    let includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

struct OAIResponseFormat: Encodable, Sendable {
    let type: String
}

struct OAIMessage: Encodable, Sendable {
    let role: String
    let content: OAIMessageContent?
    let toolCalls: [OAIToolCall]?
    let toolCallId: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
}

enum OAIMessageContent: Encodable, Sendable {
    case string(String)
    case parts([OAIContentPart])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        case .parts(let parts):
            var container = encoder.singleValueContainer()
            try container.encode(parts)
        }
    }
}

struct OAIContentPart: Encodable, Sendable {
    let type: String
    let text: String?
    let imageUrl: OAIImageURL?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }
}

struct OAIImageURL: Encodable, Sendable {
    let url: String
}

struct OAIToolCall: Encodable, Sendable {
    let id: String
    let type: String
    let function: OAIFunctionCall

    enum CodingKeys: String, CodingKey {
        case id, type, function
    }
}

struct OAIFunctionCall: Encodable, Sendable {
    let name: String
    let arguments: String
}

struct OAITool: Encodable, Sendable {
    let type: String
    let function: OAIToolFunction
}

struct OAIToolFunction: Encodable, Sendable {
    let name: String
    let description: String
    let parameters: OAIToolParameters
}

struct OAIToolParameters: Encodable, Sendable {
    let type: String
    let properties: [String: OAIPropertySchema]
    var required: [String]?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(properties, forKey: .properties)
        try container.encodeIfPresent(required, forKey: .required)
    }

    enum CodingKeys: String, CodingKey {
        case type, properties, required
    }
}

struct OAIPropertySchema: Encodable, Sendable {
    let type: String
    let description: String?
    let enumValues: [String]?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(enumValues, forKey: .enumValues)
    }

    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
    }
}

// MARK: - Response model types

struct OAIResponse: Decodable, Sendable {
    let choices: [OAIChoice]
    let usage: OAIUsage?
}

struct OAIChoice: Decodable, Sendable {
    let message: OAIResponseMessage
    let finishReason: String?
}

struct OAIResponseMessage: Decodable, Sendable {
    let role: String
    let content: String?
    let toolCalls: [OAIResponseToolCall]?
}

struct OAIResponseToolCall: Decodable, Sendable {
    let id: String
    let type: String
    let function: OAIResponseFunction
}

struct OAIResponseFunction: Decodable, Sendable {
    let name: String
    let arguments: String
}

struct OAIUsage: Decodable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

// MARK: - Stream response types

struct OAIStreamResponse: Decodable, Sendable {
    let choices: [OAIStreamChoice]
    let usage: OAIUsage?
}

struct OAIStreamChoice: Decodable, Sendable {
    let delta: OAIDelta
    let finishReason: String?
}

struct OAIDelta: Decodable, Sendable {
    let role: String?
    let content: String?
    let toolCalls: [OAIStreamToolCall]?
}

struct OAIStreamToolCall: Decodable, Sendable {
    let index: Int
    let id: String?
    let type: String?
    let function: OAIStreamFunction?
}

struct OAIStreamFunction: Decodable, Sendable {
    let name: String?
    let arguments: String?
}

// MARK: - OpenAIProvider

public struct OpenAIProvider: ChatModelProvider {
    public let id: String
    public let displayName: String
    let baseURL: URL
    let apiKeyKeychainKey: String
    let overrideAPIKey: String?
    let networkClient: NetworkClient

    public init(
        id: String = "openai",
        displayName: String = "OpenAI",
        baseURL: URL = URL(string: "https://api.openai.com")!,
        apiKeyKeychainKey: String = "openai_api_key",
        overrideAPIKey: String? = nil,
        networkClient: NetworkClient = NetworkClient()
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.apiKeyKeychainKey = apiKeyKeychainKey
        self.overrideAPIKey = overrideAPIKey
        self.networkClient = networkClient
    }

    public var supportedCapabilities: Set<ModelCapability> {
        [.chat, .vision, .toolCalling, .streaming]
    }

    // MARK: - complete

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        let apiKey = try resolveAPIKey()
        let body = buildRequestBody(request: request, stream: false)
        let endpoint = Endpoint(
            method: .post,
            baseURL: baseURL,
            path: "/v1/chat/completions",
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ],
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

        let message = mapResponseMessage(choice.message)
        let usage = oaiResponse.usage.map { mapUsage($0) }
        let finishReason = mapFinishReason(choice.finishReason)

        return ChatResponse(message: message, usage: usage, finishReason: finishReason)
    }

    // MARK: - stream

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiKey = try resolveAPIKey()
                    let body = buildRequestBody(request: request, stream: true)
                    let endpoint = Endpoint(
                        method: .post,
                        baseURL: baseURL,
                        path: "/v1/chat/completions",
                        headers: [
                            "Authorization": "Bearer \(apiKey)",
                            "Content-Type": "application/json"
                        ],
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

                        let usage = streamResponse.usage.map { mapUsage($0) }

                        for choice in streamResponse.choices {
                            let finishReason: FinishReason? = choice.finishReason.flatMap { mapFinishReasonOptional($0) }
                            let delta = choice.delta

                            if let toolCalls = delta.toolCalls {
                                for toolCall in toolCalls {
                                    let contentDelta = ContentDelta.toolCall(
                                        index: toolCall.index,
                                        id: toolCall.id,
                                        name: toolCall.function?.name,
                                        arguments: toolCall.function?.arguments
                                    )
                                    continuation.yield(ChatStreamChunk(delta: contentDelta, finishReason: finishReason, usage: usage))
                                }
                            } else if let text = delta.content, !text.isEmpty {
                                let contentDelta = ContentDelta.text(text)
                                continuation.yield(ChatStreamChunk(delta: contentDelta, finishReason: finishReason, usage: usage))
                            } else if finishReason != nil || usage != nil {
                                // Emit a chunk for finish_reason / usage even if no content delta
                                let contentDelta = ContentDelta.text("")
                                continuation.yield(ChatStreamChunk(delta: contentDelta, finishReason: finishReason, usage: usage))
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
        if let key = overrideAPIKey { return key }
        do {
            if let key = try KeychainService.load(key: apiKeyKeychainKey) {
                return key
            }
        } catch {
            throw ProviderError.authenticationFailed("Keychain access failed for '\(apiKeyKeychainKey)': \(error.localizedDescription)")
        }
        throw ProviderError.authenticationFailed("No API key found for key '\(apiKeyKeychainKey)'")
    }

    internal func buildRequestBody(request: ChatRequest, stream: Bool) -> OAIRequestBody {
        let messages = request.messages.map { encodeMessage($0) }

        let tools: [OAITool]? = request.tools.map { toolDefs in
            toolDefs.map { def in
                let props: [String: OAIPropertySchema]
                var requiredKeys: [String]?
                if let schema = def.parameters {
                    props = schema.properties.mapValues { p in
                        OAIPropertySchema(type: p.type, description: p.description, enumValues: p.enumValues)
                    }
                    requiredKeys = schema.required.isEmpty ? nil : schema.required
                } else {
                    props = [:]
                }
                return OAITool(
                    type: "function",
                    function: OAIToolFunction(
                        name: def.name,
                        description: def.description,
                        parameters: OAIToolParameters(type: "object", properties: props, required: requiredKeys)
                    )
                )
            }
        }

        let responseFormat: OAIResponseFormat? = {
            guard let fmt = request.responseFormat else { return nil }
            switch fmt {
            case .json: return OAIResponseFormat(type: "json_object")
            case .text: return nil
            }
        }()

        let streamOptions: OAIStreamOptions? = stream ? OAIStreamOptions(includeUsage: true) : nil

        return OAIRequestBody(
            model: request.model,
            messages: messages,
            temperature: request.temperature,
            maxTokens: request.maxTokens,
            tools: tools,
            responseFormat: responseFormat,
            stream: stream,
            streamOptions: streamOptions
        )
    }

    func encodeMessage(_ message: ChatMessage) -> OAIMessage {
        switch message.role {
        case .system:
            let text = message.textContent ?? ""
            return OAIMessage(role: "system", content: .string(text), toolCalls: nil, toolCallId: nil)

        case .user:
            let hasImages = message.content.contains {
                if case .imageURL = $0 { return true }
                if case .imageBase64 = $0 { return true }
                return false
            }

            if hasImages {
                let parts = message.content.map { part -> OAIContentPart in
                    switch part {
                    case .text(let t):
                        return OAIContentPart(type: "text", text: t, imageUrl: nil)
                    case .imageURL(let url):
                        return OAIContentPart(type: "image_url", text: nil, imageUrl: OAIImageURL(url: url))
                    case .imageBase64(let data, let mediaType):
                        let dataURL = "data:\(mediaType);base64,\(data)"
                        return OAIContentPart(type: "image_url", text: nil, imageUrl: OAIImageURL(url: dataURL))
                    }
                }
                return OAIMessage(role: "user", content: .parts(parts), toolCalls: nil, toolCallId: nil)
            } else {
                let text = message.textContent ?? ""
                return OAIMessage(role: "user", content: .string(text), toolCalls: nil, toolCallId: nil)
            }

        case .assistant:
            let text = message.textContent ?? ""
            let toolCalls: [OAIToolCall]? = message.toolCalls.map { calls in
                calls.map { tc in
                    OAIToolCall(
                        id: tc.id,
                        type: "function",
                        function: OAIFunctionCall(name: tc.name, arguments: tc.arguments)
                    )
                }
            }
            return OAIMessage(role: "assistant", content: .string(text), toolCalls: toolCalls, toolCallId: nil)

        case .tool:
            let text = message.textContent ?? ""
            return OAIMessage(role: "tool", content: .string(text), toolCalls: nil, toolCallId: message.toolCallId)
        }
    }

    private func mapResponseMessage(_ oaiMsg: OAIResponseMessage) -> ChatMessage {
        let toolCalls: [ToolCall]? = oaiMsg.toolCalls.map { calls in
            calls.map { tc in
                ToolCall(id: tc.id, name: tc.function.name, arguments: tc.function.arguments)
            }
        }
        let content: [ContentPart] = [.text(oaiMsg.content ?? "")]
        return ChatMessage(role: .assistant, content: content, toolCalls: toolCalls)
    }

    private func mapUsage(_ oaiUsage: OAIUsage) -> TokenUsage {
        TokenUsage(
            promptTokens: oaiUsage.promptTokens,
            completionTokens: oaiUsage.completionTokens,
            totalTokens: oaiUsage.totalTokens
        )
    }

    private func mapFinishReason(_ raw: String?) -> FinishReason {
        mapFinishReasonOptional(raw ?? "stop") ?? .stop
    }

    private func mapFinishReasonOptional(_ raw: String) -> FinishReason? {
        switch raw {
        case "stop": return .stop
        case "tool_calls": return .toolCalls
        case "length": return .lengthLimit
        case "content_filter": return .contentFilter
        default: return nil
        }
    }

    private func mapNetworkError(_ error: NetworkError) -> Error {
        switch error {
        case .httpError(let statusCode, let data):
            let message = data.flatMap { String(data: $0, encoding: .utf8) }
            switch statusCode {
            case 401:
                return ProviderError.authenticationFailed(message ?? "Unauthorized")
            case 429:
                return ProviderError.rateLimited(retryAfter: nil)
            default:
                return ProviderError.serverError(statusCode: statusCode, message: message)
            }
        default:
            return error
        }
    }
}
