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
    public var apiKey: String?
    public var isEnabled: Bool
    public var transportType: MCPTransportType
    public var discoveredTools: [MCPToolInfo]

    public init(
        id: String = UUID().uuidString,
        name: String,
        url: String,
        apiKey: String? = nil,
        isEnabled: Bool = true,
        transportType: MCPTransportType = .httpSSE,
        discoveredTools: [MCPToolInfo] = []
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.apiKey = apiKey
        self.isEnabled = isEnabled
        self.transportType = transportType
        self.discoveredTools = discoveredTools
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

/// Persists MCP server configurations to UserDefaults.
public struct MCPConfigStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "mcp_server_configs"

    public init(defaults: UserDefaults = UserDefaults.standard) {
        self.defaults = defaults
    }

    public func loadConfigs() -> [MCPServerConfig] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MCPServerConfig].self, from: data)) ?? []
    }

    public func saveConfigs(_ configs: [MCPServerConfig]) {
        if let data = try? JSONEncoder().encode(configs) {
            defaults.set(data, forKey: key)
        }
    }
}
