import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system, user, assistant, tool
}

public struct ChatMessage: Sendable, Identifiable, Equatable {
    public let id: String
    public let role: ChatRole
    public let content: [ContentPart]
    public let toolCallId: String?
    public let toolCalls: [ToolCall]?
    public var citations: [MessageCitation]

    public init(
        id: String = UUID().uuidString,
        role: ChatRole,
        content: [ContentPart],
        toolCallId: String? = nil,
        toolCalls: [ToolCall]? = nil,
        citations: [MessageCitation] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
        self.citations = citations
    }

    public var textContent: String? {
        content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.first
    }

    public static func system(_ text: String, citations: [MessageCitation] = []) -> ChatMessage {
        ChatMessage(role: .system, content: [.text(text)], citations: citations)
    }
    public static func user(_ text: String, citations: [MessageCitation] = []) -> ChatMessage {
        ChatMessage(role: .user, content: [.text(text)], citations: citations)
    }
    public static func assistant(_ text: String, toolCalls: [ToolCall]? = nil, citations: [MessageCitation] = []) -> ChatMessage {
        ChatMessage(role: .assistant, content: [.text(text)], toolCalls: toolCalls, citations: citations)
    }
    public static func toolResult(toolCallId: String, content: String, citations: [MessageCitation] = []) -> ChatMessage {
        ChatMessage(role: .tool, content: [.text(content)], toolCallId: toolCallId, citations: citations)
    }
}

extension ChatMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, role, content, toolCallId, toolCalls, citations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.role = try c.decode(ChatRole.self, forKey: .role)
        self.content = try c.decode([ContentPart].self, forKey: .content)
        self.toolCallId = try c.decodeIfPresent(String.self, forKey: .toolCallId)
        self.toolCalls = try c.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        self.citations = try c.decodeIfPresent([MessageCitation].self, forKey: .citations) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(toolCallId, forKey: .toolCallId)
        try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try c.encode(citations, forKey: .citations)
    }
}

public enum ContentPart: Codable, Sendable, Equatable {
    case text(String)
    case imageURL(String)
    case imageBase64(data: String, mediaType: String)

    private enum CodingKeys: String, CodingKey { case type, text, url, data, mediaType = "media_type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text": self = .text(try container.decode(String.self, forKey: .text))
        case "image_url": self = .imageURL(try container.decode(String.self, forKey: .url))
        case "image_base64": self = .imageBase64(data: try container.decode(String.self, forKey: .data), mediaType: try container.decode(String.self, forKey: .mediaType))
        default: self = .text("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text): try container.encode("text", forKey: .type); try container.encode(text, forKey: .text)
        case .imageURL(let url): try container.encode("image_url", forKey: .type); try container.encode(url, forKey: .url)
        case .imageBase64(let data, let mt): try container.encode("image_base64", forKey: .type); try container.encode(data, forKey: .data); try container.encode(mt, forKey: .mediaType)
        }
    }
}

public struct ToolCall: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let arguments: String
    public init(id: String, name: String, arguments: String) { self.id = id; self.name = name; self.arguments = arguments }
}
