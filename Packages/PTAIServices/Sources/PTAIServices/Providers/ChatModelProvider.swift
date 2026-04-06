import Foundation

public protocol ChatModelProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var supportedCapabilities: Set<ModelCapability> { get }
    func complete(_ request: ChatRequest) async throws -> ChatResponse
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error>
}

public struct ChatRequest: Sendable {
    public let messages: [ChatMessage]
    public let model: String
    public let temperature: Double?
    public let maxTokens: Int?
    public let tools: [ToolDefinition]?
    public let thinkingLevel: ThinkingLevel?
    public let responseFormat: ResponseFormat?

    public init(messages: [ChatMessage], model: String, temperature: Double? = nil, maxTokens: Int? = nil, tools: [ToolDefinition]? = nil, thinkingLevel: ThinkingLevel? = nil, responseFormat: ResponseFormat? = nil) {
        self.messages = messages; self.model = model; self.temperature = temperature; self.maxTokens = maxTokens; self.tools = tools; self.thinkingLevel = thinkingLevel; self.responseFormat = responseFormat
    }
}

public struct ChatResponse: Sendable {
    public let message: ChatMessage
    public let usage: TokenUsage?
    public let finishReason: FinishReason
    public init(message: ChatMessage, usage: TokenUsage? = nil, finishReason: FinishReason = .stop) {
        self.message = message; self.usage = usage; self.finishReason = finishReason
    }
}

public struct ChatStreamChunk: Sendable {
    public let delta: ContentDelta
    public let finishReason: FinishReason?
    public let usage: TokenUsage?
    public init(delta: ContentDelta, finishReason: FinishReason? = nil, usage: TokenUsage? = nil) {
        self.delta = delta; self.finishReason = finishReason; self.usage = usage
    }
}

public enum ContentDelta: Sendable {
    case text(String)
    case toolCall(index: Int, id: String?, name: String?, arguments: String?)
    case thinking(String)
}

public enum FinishReason: String, Codable, Sendable { case stop, toolCalls = "tool_calls", lengthLimit = "length", contentFilter = "content_filter" }
public enum ThinkingLevel: String, Codable, Sendable, CaseIterable { case off, minimal, low, medium, high }
public enum ResponseFormat: Sendable { case text, json }

public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let parameters: ToolParametersSchema?
    public init(name: String, description: String, parameters: ToolParametersSchema? = nil) {
        self.name = name; self.description = description; self.parameters = parameters
    }
}

public struct ToolParametersSchema: Sendable {
    public let properties: [String: ToolPropertySchema]
    public let required: [String]
    public init(properties: [String: ToolPropertySchema], required: [String] = []) {
        self.properties = properties; self.required = required
    }
}

public struct ToolPropertySchema: Sendable {
    public let type: String
    public let description: String?
    public let enumValues: [String]?
    public init(type: String, description: String? = nil, enumValues: [String]? = nil) {
        self.type = type; self.description = description; self.enumValues = enumValues
    }
}
