import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system, user, assistant, tool
}

public struct ChatMessage: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let role: ChatRole
    public let content: [ContentPart]
    public let toolCallId: String?
    public let toolCalls: [ToolCall]?

    public init(id: String = UUID().uuidString, role: ChatRole, content: [ContentPart], toolCallId: String? = nil, toolCalls: [ToolCall]? = nil) {
        self.id = id; self.role = role; self.content = content; self.toolCallId = toolCallId; self.toolCalls = toolCalls
    }

    public var textContent: String? {
        content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.first
    }

    public static func system(_ text: String) -> ChatMessage { ChatMessage(role: .system, content: [.text(text)]) }
    public static func user(_ text: String) -> ChatMessage { ChatMessage(role: .user, content: [.text(text)]) }
    public static func assistant(_ text: String, toolCalls: [ToolCall]? = nil) -> ChatMessage { ChatMessage(role: .assistant, content: [.text(text)], toolCalls: toolCalls) }
    public static func toolResult(toolCallId: String, content: String) -> ChatMessage { ChatMessage(role: .tool, content: [.text(content)], toolCallId: toolCallId) }
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
