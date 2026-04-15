import Foundation
import PTCore

/// Transport mechanism for MCP server communication.
public enum MCPTransportType: String, Codable, Sendable, CaseIterable {
    /// HTTP POST for requests, Server-Sent Events for notifications.
    case httpSSE = "http_sse"
    /// Standard I/O (stdin/stdout) for local process-based servers.
    case stdio = "stdio"
}

/// Model Context Protocol server configuration and connection state.
///
/// Stores server endpoints, authentication, and discovered tools for MCP integration.
public struct MCPServerConfig: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var url: String
    /// Transient in-memory API key. Never encoded to JSON — MCPServerStore persists this in Keychain.
    public var apiKey: String?
    public var isEnabled: Bool
    public var transportType: MCPTransportType
    public var discoveredTools: [MCPToolInfo]
    public var command: String?
    public var arguments: [String]
    public var environment: [String: String]
    /// Transient in-memory headers. Never encoded to JSON — MCPServerStore persists these in Keychain.
    public var customHeaders: [String: String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        url: String,
        apiKey: String? = nil,
        isEnabled: Bool = true,
        transportType: MCPTransportType = .httpSSE,
        discoveredTools: [MCPToolInfo] = [],
        command: String? = nil,
        arguments: [String] = [],
        environment: [String: String] = [:],
        customHeaders: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.apiKey = apiKey
        self.isEnabled = isEnabled
        self.transportType = transportType
        self.discoveredTools = discoveredTools
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.customHeaders = customHeaders
    }

    // Invariant: `apiKey` and `customHeaders` are secrets — they MUST NOT appear in the JSON payload.
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case isEnabled
        case transportType
        case discoveredTools
        case command
        case arguments
        case environment
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.url = try c.decode(String.self, forKey: .url)
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.transportType = try c.decodeIfPresent(MCPTransportType.self, forKey: .transportType) ?? .httpSSE
        self.discoveredTools = try c.decodeIfPresent([MCPToolInfo].self, forKey: .discoveredTools) ?? []
        self.command = try c.decodeIfPresent(String.self, forKey: .command)
        self.arguments = try c.decodeIfPresent([String].self, forKey: .arguments) ?? []
        self.environment = try c.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        self.apiKey = nil
        self.customHeaders = [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(url, forKey: .url)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(transportType, forKey: .transportType)
        try c.encode(discoveredTools, forKey: .discoveredTools)
        try c.encodeIfPresent(command, forKey: .command)
        if !arguments.isEmpty {
            try c.encode(arguments, forKey: .arguments)
        }
        if !environment.isEmpty {
            try c.encode(environment, forKey: .environment)
        }
    }
}

/// Information about a tool discovered from an MCP server.
public struct MCPToolInfo: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let parametersSchema: String?

    public init(name: String, description: String, parametersSchema: String? = nil) {
        self.name = name
        self.description = description
        self.parametersSchema = parametersSchema
    }
}

/// Connection status for an MCP server.
public enum MCPConnectionStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(toolCount: Int)
    case error(String)

    public var displayText: String {
        switch self {
        case .disconnected:
            return AppLocalization.string("common.disconnected")
        case .connecting:
            return AppLocalization.string("common.connecting_ellipsis")
        case .connected(let count):
            return AppLocalization.format("common.connected_tool_count_format", locale: .autoupdatingCurrent, count)
        case .error(let msg):
            return AppLocalization.format(
                "common.error_detail_format",
                fallback: "%@",
                locale: .autoupdatingCurrent,
                msg
            )
        }
    }

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

