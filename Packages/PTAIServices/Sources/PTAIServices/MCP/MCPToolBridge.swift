import Foundation

/// Bridges an MCP server tool into the local AITool system.
///
/// Wraps an `MCPClient` and its tool metadata so that MCP tools appear
/// alongside built-in tools in the `ToolRegistry`.
public struct MCPBridgedTool: AITool, Sendable {
    public static var name: String { "mcp_bridged" }
    public static var description: String { "Bridged MCP tool" }
    public static var category: ToolCategory { .utility }
    public static var riskLevel: ToolRiskLevel { .moderate }

    /// The actual tool name on the MCP server.
    public let toolName: String
    /// Human-readable description from MCP server.
    public let toolDescription: String
    /// The MCP client to call through.
    public let client: MCPClient
    /// Original MCP tool info for schema access.
    public let toolInfo: MCPToolInfo

    public init(client: MCPClient, toolInfo: MCPToolInfo) {
        self.client = client
        self.toolInfo = toolInfo
        self.toolName = toolInfo.name
        self.toolDescription = toolInfo.description
    }

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        let result = try await client.callTool(name: toolName, arguments: arguments)
        return ToolResult(
            content: result.textContent.isEmpty ? "{}" : result.textContent,
            isError: result.isError
        )
    }
}

// MARK: - ToolRegistry MCP Integration

public extension ToolRegistry {
    /// Discover and register all tools from an MCP client into this registry.
    ///
    /// Each MCP tool is wrapped as an `MCPBridgedTool` and registered with
    /// a prefixed name (`mcp_<serverName>_<toolName>`) to avoid collisions.
    ///
    /// - Parameters:
    ///   - client: An initialized MCP client.
    ///   - serverName: A short identifier for the server, used as a tool name prefix.
    /// - Returns: The list of discovered `MCPToolInfo` entries.
    @discardableResult
    func registerMCPTools(from client: MCPClient, serverName: String) async throws -> [MCPToolInfo] {
        let tools = try await client.listTools()

        for toolInfo in tools {
            let bridged = MCPBridgedTool(client: client, toolInfo: toolInfo)
            mcpToolStore.register(
                name: mcpToolName(server: serverName, tool: toolInfo.name),
                tool: bridged,
                info: toolInfo
            )
        }

        return tools
    }

    /// Look up an MCP-bridged tool by its prefixed name.
    func mcpTool(named name: String) -> MCPBridgedTool? {
        mcpToolStore.tool(named: name)
    }

    /// All registered MCP tools and their info.
    var mcpTools: [(name: String, tool: MCPBridgedTool, info: MCPToolInfo)] {
        mcpToolStore.allTools
    }

    /// Remove all MCP tools registered from a specific server.
    func unregisterMCPTools(serverName: String) {
        mcpToolStore.removeTools(forServer: serverName)
    }

    /// Generate tool definitions for MCP tools suitable for LLM API calls.
    func mcpToolDefinitions() -> [ToolDefinition] {
        mcpToolStore.allTools.map { entry in
            ToolDefinition(
                name: entry.name,
                description: entry.info.description,
                parameters: entry.info.parametersSchema.flatMap(parseParametersSchema)
            )
        }
    }

    private func mcpToolName(server: String, tool: String) -> String {
        "mcp_\(server)_\(tool)"
    }

    private func parseParametersSchema(_ json: String) -> ToolParametersSchema? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let properties = dict["properties"] as? [String: Any] else {
            return nil
        }

        var props: [String: ToolPropertySchema] = [:]
        for (key, value) in properties {
            guard let propDict = value as? [String: Any] else { continue }
            props[key] = ToolPropertySchema(
                type: propDict["type"] as? String ?? "string",
                description: propDict["description"] as? String
            )
        }

        let required = dict["required"] as? [String] ?? []
        return ToolParametersSchema(properties: props, required: required)
    }
}

// MARK: - MCP Tool Store

/// Thread-safe storage for MCP-bridged tools, attached to ToolRegistry.
///
/// Uses a simple lock-based approach since ToolRegistry is `@unchecked Sendable`.
final class MCPToolStore: @unchecked Sendable {
    private let lock = NSLock()
    private var tools: [String: (tool: MCPBridgedTool, info: MCPToolInfo)] = [:]

    func register(name: String, tool: MCPBridgedTool, info: MCPToolInfo) {
        lock.lock()
        defer { lock.unlock() }
        tools[name] = (tool, info)
    }

    func tool(named name: String) -> MCPBridgedTool? {
        lock.lock()
        defer { lock.unlock() }
        return tools[name]?.tool
    }

    var allTools: [(name: String, tool: MCPBridgedTool, info: MCPToolInfo)] {
        lock.lock()
        defer { lock.unlock() }
        return tools.map { (name: $0.key, tool: $0.value.tool, info: $0.value.info) }
    }

    func removeTools(forServer serverName: String) {
        lock.lock()
        defer { lock.unlock() }
        let prefix = "mcp_\(serverName)_"
        tools = tools.filter { !$0.key.hasPrefix(prefix) }
    }
}

// MARK: - ToolRegistry MCPToolStore Association

private var mcpToolStoreKey: UInt8 = 0

extension ToolRegistry {
    var mcpToolStore: MCPToolStore {
        if let existing = objc_getAssociatedObject(self, &mcpToolStoreKey) as? MCPToolStore {
            return existing
        }
        let store = MCPToolStore()
        objc_setAssociatedObject(self, &mcpToolStoreKey, store, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return store
    }
}
