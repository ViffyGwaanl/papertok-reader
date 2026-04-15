import Foundation
import PTCore
import PTNetworking

// MARK: - Request JSON types

struct GeminiRequestBody: Encodable, Sendable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiContent?
    let generationConfig: GeminiGenerationConfig?
    let tools: [GeminiTool]?
    let safetySettings: [GeminiSafetySetting]?

    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction = "system_instruction"
        case generationConfig = "generation_config"
        case tools
        case safetySettings = "safety_settings"
    }
}

struct GeminiContent: Encodable, Sendable {
    let role: String?
    let parts: [GeminiPart]
}

enum GeminiPart: Encodable, Sendable {
    case text(String)
    case inlineData(mimeType: String, data: String)
    case functionCall(name: String, args: String)
    case functionResponse(name: String, response: String)

    private enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
        case functionCall = "function_call"
        case functionResponse = "function_response"
    }

    private struct InlineData: Encodable {
        let mimeType: String
        let data: String
        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }
    }

    private struct FunctionCall: Encodable {
        let name: String
        let args: GeminiJSONValue
    }

    private struct FunctionResponse: Encodable {
        let name: String
        let response: GeminiJSONValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try container.encode(t, forKey: .text)
        case .inlineData(let mime, let data):
            try container.encode(InlineData(mimeType: mime, data: data), forKey: .inlineData)
        case .functionCall(let name, let args):
            let value = GeminiJSONValue.parse(args) ?? .object([:])
            try container.encode(FunctionCall(name: name, args: value), forKey: .functionCall)
        case .functionResponse(let name, let response):
            let value = GeminiJSONValue.parse(response) ?? .object([:])
            try container.encode(FunctionResponse(name: name, response: value), forKey: .functionResponse)
        }
    }
}

struct GeminiGenerationConfig: Encodable, Sendable {
    let temperature: Double?
    let maxOutputTokens: Int?
    let topP: Double?
    let stopSequences: [String]?
    let responseMimeType: String?
    let thinkingConfig: GeminiThinkingConfig?

    enum CodingKeys: String, CodingKey {
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case topP
        case stopSequences
        case responseMimeType = "response_mime_type"
        case thinkingConfig = "thinking_config"
    }
}

struct GeminiThinkingConfig: Encodable, Sendable {
    let includeThoughts: Bool?
    let thinkingBudget: Int?

    enum CodingKeys: String, CodingKey {
        case includeThoughts
        case thinkingBudget
    }
}

struct GeminiTool: Encodable, Sendable {
    let functionDeclarations: [GeminiFunctionDeclaration]

    enum CodingKeys: String, CodingKey {
        case functionDeclarations = "function_declarations"
    }
}

struct GeminiFunctionDeclaration: Encodable, Sendable {
    let name: String
    let description: String
    let parameters: GeminiSchema
}

struct GeminiSchema: Encodable, Sendable {
    let type: String
    let properties: [String: GeminiPropertySchema]
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

struct GeminiPropertySchema: Encodable, Sendable {
    let type: String
    let description: String?
    let enumValues: [String]?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type.uppercased(), forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(enumValues, forKey: .enumValues)
    }

    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
    }
}

struct GeminiSafetySetting: Encodable, Sendable {
    let category: String
    let threshold: String
}

// MARK: - Arbitrary JSON value for encode/decode

enum GeminiJSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([GeminiJSONValue])
    case object([String: GeminiJSONValue])
    case null

    static func parse(_ jsonString: String) -> GeminiJSONValue? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return fromAny(obj)
    }

    private static func fromAny(_ value: Any) -> GeminiJSONValue {
        if let s = value as? String { return .string(s) }
        if let b = value as? Bool, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() { return .bool(b) }
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            if n.doubleValue == Double(n.intValue) { return .int(n.intValue) }
            return .double(n.doubleValue)
        }
        if let arr = value as? [Any] { return .array(arr.map { fromAny($0) }) }
        if let dict = value as? [String: Any] { return .object(dict.mapValues { fromAny($0) }) }
        return .null
    }

    func toJSONString() -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self), let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([GeminiJSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: GeminiJSONValue].self) { self = .object(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Response JSON types

struct GeminiResponse: Decodable, Sendable {
    let candidates: [GeminiCandidate]?
    let usageMetadata: GeminiUsageMetadata?

    enum CodingKeys: String, CodingKey {
        case candidates
        case usageMetadata = "usageMetadata"
    }
}

struct GeminiCandidate: Decodable, Sendable {
    let content: GeminiResponseContent?
    let finishReason: String?
}

struct GeminiResponseContent: Decodable, Sendable {
    let role: String?
    let parts: [GeminiResponsePart]?
}

struct GeminiResponsePart: Decodable, Sendable {
    let text: String?
    let functionCall: GeminiResponseFunctionCall?
    let thought: Bool?

    enum CodingKeys: String, CodingKey {
        case text
        case functionCall
        case thought
    }
}

struct GeminiResponseFunctionCall: Decodable, Sendable {
    let name: String
    let args: GeminiJSONValue?
}

struct GeminiUsageMetadata: Decodable, Sendable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
}

// MARK: - GeminiProvider

public struct GeminiProvider: ChatModelProvider {
    public let id: String
    public let displayName: String
    let baseURL: URL
    let apiKeyKeychainKey: String
    let overrideAPIKey: String?
    let includeThoughts: Bool
    let safetyPreset: GeminiSafetyPreset
    let keyResolver: (@Sendable () -> String?)?
    let networkClient: NetworkClient

    public init(
        id: String = "gemini",
        displayName: String = "Google Gemini",
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!,
        apiKeyKeychainKey: String = "gemini_api_key",
        overrideAPIKey: String? = nil,
        includeThoughts: Bool = false,
        safetyPreset: GeminiSafetyPreset = .default,
        keyResolver: (@Sendable () -> String?)? = nil,
        networkClient: NetworkClient = NetworkClient()
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.apiKeyKeychainKey = apiKeyKeychainKey
        self.overrideAPIKey = overrideAPIKey
        self.includeThoughts = includeThoughts
        self.safetyPreset = safetyPreset
        self.keyResolver = keyResolver
        self.networkClient = networkClient
    }

    public var supportedCapabilities: Set<ModelCapability> {
        [.chat, .vision, .toolCalling, .streaming, .thinking]
    }

    // MARK: - complete

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        let apiKey = try resolveAPIKey()
        let body = buildRequestBody(request: request)
        let path = "/v1beta/models/\(request.model):generateContent"

        let endpoint = Endpoint(
            method: .post,
            baseURL: baseURL,
            path: path,
            headers: ["Content-Type": "application/json"],
            queryItems: [URLQueryItem(name: "key", value: apiKey)],
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
        let geminiResponse = try decoder.decode(GeminiResponse.self, from: data)

        guard let candidate = geminiResponse.candidates?.first else {
            throw ProviderError.serverError(statusCode: 200, message: "No candidates in Gemini response")
        }

        let message = mapCandidateToMessage(candidate)
        let usage = geminiResponse.usageMetadata.map { mapUsage($0) }
        let finishReason = mapFinishReason(candidate.finishReason)

        return ChatResponse(message: message, usage: usage, finishReason: finishReason)
    }

    // MARK: - stream

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiKey = try resolveAPIKey()
                    let body = buildRequestBody(request: request)
                    let path = "/v1beta/models/\(request.model):streamGenerateContent"
                    let endpoint = Endpoint(
                        method: .post,
                        baseURL: baseURL,
                        path: path,
                        headers: ["Content-Type": "application/json"],
                        queryItems: [
                            URLQueryItem(name: "alt", value: "sse"),
                            URLQueryItem(name: "key", value: apiKey),
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
                    var toolCallIndex = 0

                    for try await event in SSEParser.events(from: bytes) {
                        if event.isDone { break }
                        guard let data = event.data.data(using: .utf8) else { continue }
                        let response: GeminiResponse
                        do {
                            response = try decoder.decode(GeminiResponse.self, from: data)
                        } catch {
                            continue
                        }

                        let usage = response.usageMetadata.map { mapUsage($0) }

                        for candidate in response.candidates ?? [] {
                            let finishReason = candidate.finishReason.flatMap { mapFinishReasonOptional($0) }

                            if let parts = candidate.content?.parts {
                                for part in parts {
                                    if let fc = part.functionCall {
                                        let args = fc.args?.toJSONString() ?? "{}"
                                        continuation.yield(ChatStreamChunk(
                                            delta: .toolCall(
                                                index: toolCallIndex,
                                                id: "\(fc.name)_\(toolCallIndex)",
                                                name: fc.name,
                                                arguments: args
                                            ),
                                            finishReason: finishReason,
                                            usage: usage
                                        ))
                                        toolCallIndex += 1
                                    } else if let text = part.text, !text.isEmpty {
                                        if part.thought == true {
                                            continuation.yield(ChatStreamChunk(
                                                delta: .thinking(text),
                                                finishReason: finishReason,
                                                usage: usage
                                            ))
                                        } else {
                                            continuation.yield(ChatStreamChunk(
                                                delta: .text(text),
                                                finishReason: finishReason,
                                                usage: usage
                                            ))
                                        }
                                    }
                                }
                            } else if finishReason != nil || usage != nil {
                                continuation.yield(ChatStreamChunk(
                                    delta: .text(""),
                                    finishReason: finishReason,
                                    usage: usage
                                ))
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

    func buildRequestBody(request: ChatRequest) -> GeminiRequestBody {
        var systemText: String? = nil
        var contents: [GeminiContent] = []

        for msg in request.messages {
            if msg.role == .system {
                if let t = msg.textContent, !t.isEmpty {
                    if let existing = systemText {
                        systemText = existing + "\n" + t
                    } else {
                        systemText = t
                    }
                }
            } else {
                contents.append(encodeMessage(msg))
            }
        }

        let systemInstruction: GeminiContent? = systemText.map {
            GeminiContent(role: nil, parts: [.text($0)])
        }

        let tools: [GeminiTool]? = request.tools.flatMap { toolDefs -> [GeminiTool]? in
            guard !toolDefs.isEmpty else { return nil }
            let decls: [GeminiFunctionDeclaration] = toolDefs.map { def in
                let props: [String: GeminiPropertySchema]
                var requiredKeys: [String]?
                if let schema = def.parameters {
                    props = schema.properties.mapValues { p in
                        GeminiPropertySchema(type: p.type, description: p.description, enumValues: p.enumValues)
                    }
                    requiredKeys = schema.required.isEmpty ? nil : schema.required
                } else {
                    props = [:]
                }
                return GeminiFunctionDeclaration(
                    name: def.name,
                    description: def.description,
                    parameters: GeminiSchema(type: "OBJECT", properties: props, required: requiredKeys)
                )
            }
            return [GeminiTool(functionDeclarations: decls)]
        }

        let generationConfig: GeminiGenerationConfig? = {
            let thinkingConfig = buildThinkingConfig(
                for: request.thinkingLevel,
                explicitBudget: request.thinkingBudgetTokens
            )
            let responseMime: String? = {
                guard let fmt = request.responseFormat else { return nil }
                switch fmt {
                case .json: return "application/json"
                case .text: return nil
                }
            }()
            if request.temperature == nil,
               request.maxTokens == nil,
               request.topP == nil,
               request.stopSequences == nil,
               responseMime == nil,
               thinkingConfig == nil {
                return nil
            }
            return GeminiGenerationConfig(
                temperature: request.temperature,
                maxOutputTokens: request.maxTokens,
                topP: request.topP,
                stopSequences: request.stopSequences,
                responseMimeType: responseMime,
                thinkingConfig: thinkingConfig
            )
        }()

        return GeminiRequestBody(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: generationConfig,
            tools: tools,
            safetySettings: configuredSafetySettings()
        )
    }

    private func buildThinkingConfig(
        for level: ThinkingLevel?,
        explicitBudget: Int? = nil
    ) -> GeminiThinkingConfig? {
        let thinkingBudget: Int? = {
            if let explicit = explicitBudget, explicit > 0 { return explicit }
            return level.map(thinkingBudget(for:))
        }()
        if includeThoughts == false, thinkingBudget == nil {
            return nil
        }
        return GeminiThinkingConfig(
            includeThoughts: includeThoughts ? true : nil,
            thinkingBudget: thinkingBudget
        )
    }

    private func thinkingBudget(for level: ThinkingLevel) -> Int {
        switch level {
        case .off:
            return 0
        case .minimal:
            return 1_024
        case .low:
            return 4_096
        case .medium:
            return 8_192
        case .high:
            return 24_576
        }
    }

    private func configuredSafetySettings() -> [GeminiSafetySetting]? {
        let threshold: String
        switch safetyPreset {
        case .default:
            return nil
        case .strict:
            threshold = "BLOCK_LOW_AND_ABOVE"
        case .relaxed:
            threshold = "BLOCK_ONLY_HIGH"
        }

        return [
            "HARM_CATEGORY_HARASSMENT",
            "HARM_CATEGORY_HATE_SPEECH",
            "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            "HARM_CATEGORY_DANGEROUS_CONTENT",
        ].map { GeminiSafetySetting(category: $0, threshold: threshold) }
    }

    func encodeMessage(_ message: ChatMessage) -> GeminiContent {
        switch message.role {
        case .system:
            // Handled in buildRequestBody
            return GeminiContent(role: "user", parts: [.text(message.textContent ?? "")])

        case .user:
            let parts: [GeminiPart] = message.content.map { part in
                switch part {
                case .text(let t):
                    return .text(t)
                case .imageURL(let url):
                    return .text("[Image: \(url)]")
                case .imageBase64(let data, let mediaType):
                    return .inlineData(mimeType: mediaType, data: data)
                }
            }
            return GeminiContent(role: "user", parts: parts.isEmpty ? [.text("")] : parts)

        case .assistant:
            var parts: [GeminiPart] = []
            if let text = message.textContent, !text.isEmpty {
                parts.append(.text(text))
            }
            if let toolCalls = message.toolCalls {
                for tc in toolCalls {
                    parts.append(.functionCall(name: tc.name, args: tc.arguments))
                }
            }
            if parts.isEmpty {
                parts.append(.text(""))
            }
            return GeminiContent(role: "model", parts: parts)

        case .tool:
            let text = message.textContent ?? ""
            // Gemini expects function responses under role=user with function_response parts.
            // Use toolCallId as the function name fallback.
            let name = message.toolCallId ?? "tool"
            // Wrap string content as a JSON object for function_response.response
            let wrapped = "{\"result\":\(jsonStringEscape(text))}"
            return GeminiContent(role: "user", parts: [.functionResponse(name: name, response: wrapped)])
        }
    }

    private func jsonStringEscape(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed]),
              let str = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        // str looks like ["..."], extract the inner quoted
        let trimmed = str.dropFirst().dropLast()
        return String(trimmed)
    }

    private func mapCandidateToMessage(_ candidate: GeminiCandidate) -> ChatMessage {
        var textParts: [String] = []
        var toolCalls: [ToolCall] = []

        if let parts = candidate.content?.parts {
            for (idx, part) in parts.enumerated() {
                if let fc = part.functionCall {
                    let args = fc.args?.toJSONString() ?? "{}"
                    toolCalls.append(ToolCall(id: "\(fc.name)_\(idx)", name: fc.name, arguments: args))
                } else if let text = part.text {
                    if part.thought == true {
                        textParts.append("[thinking]\(text)[/thinking]")
                    } else {
                        textParts.append(text)
                    }
                }
            }
        }

        let content: [ContentPart] = [.text(textParts.joined())]
        return ChatMessage(
            role: .assistant,
            content: content,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )
    }

    private func mapUsage(_ u: GeminiUsageMetadata) -> TokenUsage {
        let prompt = u.promptTokenCount ?? 0
        let completion = u.candidatesTokenCount ?? 0
        let total = u.totalTokenCount ?? (prompt + completion)
        return TokenUsage(
            promptTokens: prompt,
            completionTokens: completion,
            totalTokens: total
        )
    }

    private func mapFinishReason(_ raw: String?) -> FinishReason {
        mapFinishReasonOptional(raw ?? "STOP") ?? .stop
    }

    private func mapFinishReasonOptional(_ raw: String) -> FinishReason? {
        switch raw.uppercased() {
        case "STOP": return .stop
        case "MAX_TOKENS": return .lengthLimit
        case "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII": return .contentFilter
        case "TOOL_CALLS", "FUNCTION_CALL": return .toolCalls
        default: return nil
        }
    }

    private func mapNetworkError(_ error: NetworkError) -> Error {
        switch error {
        case .httpError(let statusCode, let data):
            let message = data.flatMap { String(data: $0, encoding: .utf8) }
            switch statusCode {
            case 401, 403:
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
