import Foundation

// MARK: - JSON-RPC 2.0 Message Types

/// JSON-RPC 2.0 request for MCP protocol communication.
public struct MCPRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int
    public let method: String
    public let params: [String: AnyCodable]?

    public init(id: Int, method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 response from an MCP server.
public struct MCPResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int?
    public let result: AnyCodable?
    public let error: MCPError?

    public init(jsonrpc: String = "2.0", id: Int?, result: AnyCodable? = nil, error: MCPError? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }

    public var isError: Bool { error != nil }
}

/// JSON-RPC 2.0 error object.
public struct MCPError: Codable, Sendable, LocalizedError {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { "MCP error \(code): \(message)" }

    // Standard JSON-RPC error codes
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

/// JSON-RPC 2.0 notification (no id, no response expected).
public struct MCPNotification: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: AnyCodable?

    public init(method: String, params: AnyCodable? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

// MARK: - MCP Domain Types

/// Server capabilities returned during initialization.
public struct MCPServerCapabilities: Codable, Sendable {
    public let tools: ToolsCapability?
    public let resources: ResourcesCapability?
    public let prompts: PromptsCapability?

    public struct ToolsCapability: Codable, Sendable {
        public let listChanged: Bool?
    }

    public struct ResourcesCapability: Codable, Sendable {
        public let subscribe: Bool?
        public let listChanged: Bool?
    }

    public struct PromptsCapability: Codable, Sendable {
        public let listChanged: Bool?
    }
}

/// Result of calling an MCP tool.
public struct MCPToolResult: Sendable {
    public let content: [MCPContent]
    public let isError: Bool

    public init(content: [MCPContent], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    /// Concatenate all text content pieces.
    public var textContent: String {
        content.compactMap {
            if case .text(let t) = $0 { return t }
            return nil
        }.joined(separator: "\n")
    }
}

/// Content returned from MCP tool calls or resource reads.
public enum MCPContent: Sendable {
    case text(String)
    case image(data: String, mimeType: String)
    case resource(uri: String, text: String)
}

/// MCP resource descriptor.
public struct MCPResource: Codable, Sendable {
    public let uri: String
    public let name: String
    public let description: String?
    public let mimeType: String?
}

/// Content of an MCP resource.
public struct MCPResourceContent: Sendable {
    public let uri: String
    public let text: String?
    public let blob: String?
    public let mimeType: String?
}

// MARK: - AnyCodable

/// Type-erased Codable wrapper for arbitrary JSON values in MCP messages.
public struct AnyCodable: Codable, Sendable, Equatable {
    public let value: Any & Sendable

    public init(_ value: Any & Sendable) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value) as [Any]
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value) as [String: Any]
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0 as any Sendable) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0 as any Sendable) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported value"))
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        areEqual(lhs.value, rhs.value)
    }

    private static func areEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case (_ as NSNull, _ as NSNull):
            return true
        case let (lhs as Bool, rhs as Bool):
            return lhs == rhs
        case let (lhs as Int, rhs as Int):
            return lhs == rhs
        case let (lhs as Double, rhs as Double):
            return lhs == rhs
        case let (lhs as String, rhs as String):
            return lhs == rhs
        case let (lhs as [Any], rhs as [Any]):
            guard lhs.count == rhs.count else { return false }
            return zip(lhs, rhs).allSatisfy(areEqual)
        case let (lhs as [String: Any], rhs as [String: Any]):
            guard lhs.count == rhs.count else { return false }
            for (key, lhsValue) in lhs {
                guard let rhsValue = rhs[key], areEqual(lhsValue, rhsValue) else {
                    return false
                }
            }
            return true
        default:
            return false
        }
    }
}
