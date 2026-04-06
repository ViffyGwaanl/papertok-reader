import Foundation
import PTCore
import PTNetworking

// MARK: - Internal JSON request types

struct AnthropicRequestBody: Encodable, Sendable {
    let model: String
    let messages: [AnthropicMessage]
    let maxTokens: Int
    let system: [AnthropicSystemBlock]?
    let temperature: Double?
    let tools: [AnthropicToolDef]?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, system, temperature, tools, stream
        case maxTokens = "max_tokens"
    }
}

struct AnthropicSystemBlock: Encodable, Sendable {
    let type: String
    let text: String
}

struct AnthropicMessage: Encodable, Sendable {
    let role: String
    let content: [AnthropicContent]
}

enum AnthropicContent: Encodable, Sendable {
    case text(String)
    case image(source: AnthropicImageSource, mediaType: String)
    case toolUse(id: String, name: String, input: String)
    case toolResult(toolUseId: String, content: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, source, id, name, input
        case toolUseId = "tool_use_id"
        case content
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let source, _):
            try container.encode("image", forKey: .type)
            try container.encode(source, forKey: .source)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            // Encode input as raw JSON object
            try container.encode(RawJSON(input), forKey: .input)
        case .toolResult(let toolUseId, let content):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .content)
        }
    }
}

struct AnthropicImageSource: Encodable, Sendable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

struct AnthropicToolDef: Encodable, Sendable {
    let name: String
    let description: String
    let inputSchema: AnthropicToolInputSchema

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct AnthropicToolInputSchema: Encodable, Sendable {
    let type: String
    let properties: [String: AnthropicPropertySchema]
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

struct AnthropicPropertySchema: Encodable, Sendable {
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

/// Helper to encode a JSON string as raw JSON (not a quoted string).
private struct RawJSON: Encodable, Sendable {
    let jsonString: String

    init(_ jsonString: String) {
        self.jsonString = jsonString
    }

    func encode(to encoder: Encoder) throws {
        // Try to parse the JSON string and re-encode the parsed value
        if let data = jsonString.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data) {
            let reEncoded = try JSONSerialization.data(withJSONObject: jsonObject)
            // Use JSONDecoder trick: wrap in a single-value container
            var container = encoder.singleValueContainer()
            // We need to encode the raw JSON; use a workaround via AnyCodable-style
            try container.encode(JSONFragment(data: reEncoded))
        } else {
            // Fallback: encode as empty object
            var container = encoder.singleValueContainer()
            try container.encode([String: String]())
        }
    }
}

/// Wraps pre-serialized JSON data for encoding.
private struct JSONFragment: Encodable, Sendable {
    let data: Data

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Decode then re-encode to match the encoder's format
        let value = try JSONSerialization.jsonObject(with: data)
        if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodableValue($0) })
        } else if let arr = value as? [Any] {
            try container.encode(arr.map { AnyCodableValue($0) })
        } else {
            try container.encode([String: String]())
        }
    }
}

/// Minimal type-erased encodable for JSON values.
private struct AnyCodableValue: Encodable, Sendable {
    let value: @Sendable () -> Any

    init(_ v: Any) {
        // Capture value; we only use this synchronously during encoding
        let captured = v
        self.value = { captured }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let v = value()
        switch v {
        case let s as String: try container.encode(s)
        case let n as NSNumber:
            // Distinguish bool from number
            if CFBooleanGetTypeID() == CFGetTypeID(n) {
                try container.encode(n.boolValue)
            } else if n.doubleValue == Double(n.intValue) {
                try container.encode(n.intValue)
            } else {
                try container.encode(n.doubleValue)
            }
        case let a as [Any]: try container.encode(a.map { AnyCodableValue($0) })
        case let d as [String: Any]: try container.encode(d.mapValues { AnyCodableValue($0) })
        case is NSNull: try container.encodeNil()
        default: try container.encodeNil()
        }
    }
}

// MARK: - Response model types

struct AnthropicResponse: Decodable, Sendable {
    let id: String
    let type: String
    let role: String
    let content: [AnthropicContentBlock]
    let stopReason: String?
    let usage: AnthropicUsage?

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, usage
        case stopReason = "stop_reason"
    }
}

struct AnthropicContentBlock: Decodable, Sendable {
    let type: String
    let text: String?
    // tool_use fields
    let id: String?
    let name: String?
    let input: AnyCodableInput?
    // thinking fields
    let thinking: String?
}

/// Captures arbitrary JSON for tool_use input decoding.
struct AnyCodableInput: Decodable, Sendable {
    let jsonString: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Decode as raw JSON via Data round-trip
        if let dict = try? container.decode([String: CodableAnyValue].self) {
            let data = try JSONEncoder().encode(dict)
            jsonString = String(data: data, encoding: .utf8) ?? "{}"
        } else if let arr = try? container.decode([CodableAnyValue].self) {
            let data = try JSONEncoder().encode(arr)
            jsonString = String(data: data, encoding: .utf8) ?? "[]"
        } else if let str = try? container.decode(String.self) {
            jsonString = "\"\(str)\""
        } else {
            jsonString = "{}"
        }
    }

    init(jsonString: String) {
        self.jsonString = jsonString
    }
}

/// Minimal type-erased codable for JSON values in decoding.
private enum CodableAnyValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([CodableAnyValue])
    case dict([String: CodableAnyValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([CodableAnyValue].self) { self = .array(v) }
        else if let v = try? container.decode([String: CodableAnyValue].self) { self = .dict(v) }
        else if container.decodeNil() { self = .null }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dict(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

struct AnthropicUsage: Decodable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Stream event types

struct AnthropicStreamEvent: Decodable, Sendable {
    let type: String
    let message: AnthropicStreamMessage?
    let index: Int?
    let contentBlock: AnthropicContentBlock?
    let delta: AnthropicStreamDelta?
    let usage: AnthropicUsage?

    enum CodingKeys: String, CodingKey {
        case type, message, index, delta, usage
        case contentBlock = "content_block"
    }
}

struct AnthropicStreamMessage: Decodable, Sendable {
    let id: String?
    let usage: AnthropicUsage?
}

struct AnthropicStreamDelta: Decodable, Sendable {
    let type: String?
    let text: String?
    let partialJson: String?
    let thinking: String?
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case type, text, thinking
        case partialJson = "partial_json"
        case stopReason = "stop_reason"
    }
}

// MARK: - AnthropicProvider

public struct AnthropicProvider: ChatModelProvider {
    public let id: String
    public let displayName: String
    let baseURL: URL
    let apiKeyKeychainKey: String
    let overrideAPIKey: String?
    let networkClient: NetworkClient
    let defaultMaxTokens: Int

    public init(
        id: String = "anthropic",
        displayName: String = "Anthropic",
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        apiKeyKeychainKey: String = "anthropic_api_key",
        overrideAPIKey: String? = nil,
        networkClient: NetworkClient = NetworkClient(),
        defaultMaxTokens: Int = 4096
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.apiKeyKeychainKey = apiKeyKeychainKey
        self.overrideAPIKey = overrideAPIKey
        self.networkClient = networkClient
        self.defaultMaxTokens = defaultMaxTokens
    }

    public var supportedCapabilities: Set<ModelCapability> {
        [.chat, .vision, .toolCalling, .streaming, .thinking]
    }

    // MARK: - complete

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        let apiKey = try resolveAPIKey()
        let body = buildRequestBody(request: request, stream: false)
        let endpoint = Endpoint(
            method: .post,
            baseURL: baseURL,
            path: "/v1/messages",
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
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
        let response = try decoder.decode(AnthropicResponse.self, from: data)

        let message = mapResponseToMessage(response)
        let usage = response.usage.map { mapUsage($0) }
        let finishReason = mapStopReason(response.stopReason)

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
                        path: "/v1/messages",
                        headers: [
                            "x-api-key": apiKey,
                            "anthropic-version": "2023-06-01",
                            "Content-Type": "application/json",
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

                    // Track current content block types by index for delta routing
                    var blockTypes: [Int: String] = [:]
                    var toolCallNames: [Int: String] = [:]
                    var toolCallIds: [Int: String] = [:]

                    for try await event in SSEParser.events(from: bytes) {
                        if event.isDone { break }

                        guard let data = event.data.data(using: .utf8) else { continue }
                        let streamEvent: AnthropicStreamEvent
                        do {
                            streamEvent = try decoder.decode(AnthropicStreamEvent.self, from: data)
                        } catch {
                            continue
                        }

                        switch streamEvent.type {
                        case "message_start":
                            // May contain usage info
                            if let msgUsage = streamEvent.message?.usage {
                                let usage = mapUsage(msgUsage)
                                continuation.yield(ChatStreamChunk(delta: .text(""), usage: usage))
                            }

                        case "content_block_start":
                            if let index = streamEvent.index, let block = streamEvent.contentBlock {
                                blockTypes[index] = block.type
                                if block.type == "tool_use" {
                                    toolCallIds[index] = block.id ?? ""
                                    toolCallNames[index] = block.name ?? ""
                                    // Emit initial tool_call chunk with id and name
                                    continuation.yield(ChatStreamChunk(
                                        delta: .toolCall(
                                            index: index,
                                            id: block.id,
                                            name: block.name,
                                            arguments: nil
                                        )
                                    ))
                                }
                            }

                        case "content_block_delta":
                            guard let index = streamEvent.index, let delta = streamEvent.delta else { continue }

                            switch delta.type {
                            case "text_delta":
                                if let text = delta.text, !text.isEmpty {
                                    continuation.yield(ChatStreamChunk(delta: .text(text)))
                                }

                            case "input_json_delta":
                                if let json = delta.partialJson {
                                    continuation.yield(ChatStreamChunk(
                                        delta: .toolCall(
                                            index: index,
                                            id: nil,
                                            name: nil,
                                            arguments: json
                                        )
                                    ))
                                }

                            case "thinking_delta":
                                if let thinking = delta.thinking, !thinking.isEmpty {
                                    continuation.yield(ChatStreamChunk(delta: .thinking(thinking)))
                                }

                            default:
                                break
                            }

                        case "content_block_stop":
                            if let index = streamEvent.index {
                                blockTypes.removeValue(forKey: index)
                            }

                        case "message_delta":
                            let finishReason = streamEvent.delta?.stopReason.flatMap { mapStopReasonOptional($0) }
                            let usage = streamEvent.usage.map { mapUsage($0) }
                            if finishReason != nil || usage != nil {
                                continuation.yield(ChatStreamChunk(
                                    delta: .text(""),
                                    finishReason: finishReason,
                                    usage: usage
                                ))
                            }

                        case "message_stop":
                            break

                        default:
                            break
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

    func buildRequestBody(request: ChatRequest, stream: Bool) -> AnthropicRequestBody {
        // Extract system messages as top-level system field
        var systemBlocks: [AnthropicSystemBlock] = []
        var nonSystemMessages: [ChatMessage] = []

        for msg in request.messages {
            if msg.role == .system {
                if let text = msg.textContent, !text.isEmpty {
                    systemBlocks.append(AnthropicSystemBlock(type: "text", text: text))
                }
            } else {
                nonSystemMessages.append(msg)
            }
        }

        let messages = nonSystemMessages.map { encodeMessage($0) }

        let tools: [AnthropicToolDef]? = request.tools.map { toolDefs in
            toolDefs.map { def in
                let props: [String: AnthropicPropertySchema]
                var requiredKeys: [String]?
                if let schema = def.parameters {
                    props = schema.properties.mapValues { p in
                        AnthropicPropertySchema(type: p.type, description: p.description, enumValues: p.enumValues)
                    }
                    requiredKeys = schema.required.isEmpty ? nil : schema.required
                } else {
                    props = [:]
                }
                return AnthropicToolDef(
                    name: def.name,
                    description: def.description,
                    inputSchema: AnthropicToolInputSchema(type: "object", properties: props, required: requiredKeys)
                )
            }
        }

        let maxTokens = request.maxTokens ?? defaultMaxTokens

        return AnthropicRequestBody(
            model: request.model,
            messages: messages,
            maxTokens: maxTokens,
            system: systemBlocks.isEmpty ? nil : systemBlocks,
            temperature: request.temperature,
            tools: tools,
            stream: stream
        )
    }

    func encodeMessage(_ message: ChatMessage) -> AnthropicMessage {
        switch message.role {
        case .system:
            // Should not reach here (filtered out), but handle gracefully
            let text = message.textContent ?? ""
            return AnthropicMessage(role: "user", content: [.text(text)])

        case .user:
            let contentBlocks: [AnthropicContent] = message.content.map { part in
                switch part {
                case .text(let t):
                    return .text(t)
                case .imageURL(let url):
                    // Anthropic requires base64; for URL images, pass as-is in a text note
                    return .text("[Image: \(url)]")
                case .imageBase64(let data, let mediaType):
                    return .image(
                        source: AnthropicImageSource(type: "base64", mediaType: mediaType, data: data),
                        mediaType: mediaType
                    )
                }
            }
            return AnthropicMessage(role: "user", content: contentBlocks)

        case .assistant:
            var contentBlocks: [AnthropicContent] = []
            if let text = message.textContent, !text.isEmpty {
                contentBlocks.append(.text(text))
            }
            if let toolCalls = message.toolCalls {
                for tc in toolCalls {
                    contentBlocks.append(.toolUse(id: tc.id, name: tc.name, input: tc.arguments))
                }
            }
            if contentBlocks.isEmpty {
                contentBlocks.append(.text(""))
            }
            return AnthropicMessage(role: "assistant", content: contentBlocks)

        case .tool:
            let text = message.textContent ?? ""
            let toolUseId = message.toolCallId ?? ""
            return AnthropicMessage(role: "user", content: [.toolResult(toolUseId: toolUseId, content: text)])
        }
    }

    private func mapResponseToMessage(_ response: AnthropicResponse) -> ChatMessage {
        var textParts: [String] = []
        var toolCalls: [ToolCall] = []

        for block in response.content {
            switch block.type {
            case "text":
                if let text = block.text {
                    textParts.append(text)
                }
            case "tool_use":
                if let id = block.id, let name = block.name {
                    let args = block.input?.jsonString ?? "{}"
                    toolCalls.append(ToolCall(id: id, name: name, arguments: args))
                }
            case "thinking":
                // Include thinking in text with a marker prefix for downstream handling
                if let thinking = block.thinking {
                    textParts.append("[thinking]\(thinking)[/thinking]")
                }
            default:
                break
            }
        }

        let content: [ContentPart] = [.text(textParts.joined())]
        return ChatMessage(
            role: .assistant,
            content: content,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )
    }

    private func mapUsage(_ usage: AnthropicUsage) -> TokenUsage {
        let input = usage.inputTokens ?? 0
        let output = usage.outputTokens ?? 0
        return TokenUsage(
            promptTokens: input,
            completionTokens: output,
            totalTokens: input + output
        )
    }

    private func mapStopReason(_ reason: String?) -> FinishReason {
        mapStopReasonOptional(reason ?? "end_turn") ?? .stop
    }

    private func mapStopReasonOptional(_ reason: String) -> FinishReason? {
        switch reason {
        case "end_turn", "stop": return .stop
        case "tool_use": return .toolCalls
        case "max_tokens": return .lengthLimit
        default: return nil
        }
    }

    func mapNetworkError(_ error: NetworkError) -> Error {
        switch error {
        case .httpError(let statusCode, let data):
            let message = data.flatMap { String(data: $0, encoding: .utf8) }
            switch statusCode {
            case 401:
                return ProviderError.authenticationFailed(message ?? "Unauthorized")
            case 429:
                return ProviderError.rateLimited(retryAfter: nil)
            case 529:
                return ProviderError.serverError(statusCode: 529, message: message ?? "Anthropic API overloaded")
            default:
                return ProviderError.serverError(statusCode: statusCode, message: message)
            }
        default:
            return error
        }
    }
}
