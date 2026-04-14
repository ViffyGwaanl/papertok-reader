import Foundation
import PTCore

/// MCP (Model Context Protocol) client for communicating with MCP servers.
///
/// Handles the full MCP lifecycle: initialize, discover tools/resources, call tools,
/// read resources, and shutdown. Uses a pluggable transport layer for communication.
///
/// Usage:
/// ```swift
/// let transport = MCPHTTPSSETransport(serverURL: url)
/// let client = MCPClient(transport: transport, serverName: "example")
/// let capabilities = try await client.initialize()
/// let tools = try await client.listTools()
/// let result = try await client.callTool(name: "search", arguments: ["query": "swift"])
/// try await client.shutdown()
/// ```
public actor MCPClient {
    private let transport: any MCPTransport
    private let clientName: String
    private let clientVersion: String
    private var nextId = 1
    private var serverCapabilities: MCPServerCapabilities?
    private var isInitialized = false

    public init(
        transport: any MCPTransport,
        clientName: String = "PaperTok",
        clientVersion: String = "1.0.0"
    ) {
        self.transport = transport
        self.clientName = clientName
        self.clientVersion = clientVersion
    }

    // MARK: - Lifecycle

    /// Perform the MCP initialize handshake with the server.
    ///
    /// Sends `initialize` request, stores server capabilities, and sends `initialized` notification.
    /// Returns the server's declared capabilities.
    @discardableResult
    public func initialize() async throws -> MCPServerCapabilities {
        try await transport.connect()

        let params: [String: AnyCodable] = [
            "protocolVersion": AnyCodable("2024-11-05"),
            "capabilities": AnyCodable([String: Any]()),
            "clientInfo": AnyCodable([
                "name": clientName,
                "version": clientVersion,
            ] as [String: Any]),
        ]

        let response = try await sendRequest(method: "initialize", params: params)

        guard let result = response.result else {
            if let error = response.error {
                throw error
            }
            throw MCPClientError.initializeFailed("No result in initialize response")
        }

        let capabilities = try decodeFromAnyCodable(MCPInitializeResult.self, from: result)
        serverCapabilities = capabilities.capabilities
        isInitialized = true

        // Send initialized notification (no response expected)
        let notification = MCPNotification(method: "notifications/initialized")
        let notifData = try JSONEncoder().encode(notification)

        // Send as a fire-and-forget POST
        let notifRequest = MCPRequest(id: nextRequestId(), method: "notifications/initialized")
        _ = try? await transport.send(notifRequest)

        // Suppress unused variable warning
        _ = notifData

        return capabilities.capabilities
    }

    /// Gracefully shut down the MCP connection.
    public func shutdown() async throws {
        guard isInitialized else { return }
        _ = try? await sendRequest(method: "shutdown")
        isInitialized = false
        serverCapabilities = nil
        try await transport.disconnect()
    }

    // MARK: - Tool Discovery

    /// List all tools available on the connected MCP server.
    public func listTools() async throws -> [MCPToolInfo] {
        try ensureInitialized()

        let response = try await sendRequest(method: "tools/list")

        guard let result = response.result else {
            if let error = response.error { throw error }
            return []
        }

        let listResult = try decodeFromAnyCodable(MCPToolListResult.self, from: result)
        return listResult.tools.map { tool in
            MCPToolInfo(
                name: tool.name,
                description: tool.description ?? "",
                parametersSchema: tool.inputSchema.flatMap { schemaToJSON($0) }
            )
        }
    }

    // MARK: - Tool Execution

    /// Call a tool on the MCP server with the given arguments.
    public func callTool(name: String, arguments: [String: Any] = [:]) async throws -> MCPToolResult {
        try ensureInitialized()

        let params: [String: AnyCodable] = [
            "name": AnyCodable(name),
            "arguments": AnyCodable(arguments as [String: Any]),
        ]

        let response = try await sendRequest(method: "tools/call", params: params)

        if let error = response.error {
            return MCPToolResult(
                content: [.text(error.message)],
                isError: true
            )
        }

        guard let result = response.result else {
            return MCPToolResult(content: [], isError: false)
        }

        return parseToolResult(result)
    }

    // MARK: - Resource Access

    /// List all resources available on the connected MCP server.
    public func listResources() async throws -> [MCPResource] {
        try ensureInitialized()

        let response = try await sendRequest(method: "resources/list")

        guard let result = response.result else {
            if let error = response.error { throw error }
            return []
        }

        let listResult = try decodeFromAnyCodable(MCPResourceListResult.self, from: result)
        return listResult.resources
    }

    /// Read a resource from the MCP server by URI.
    public func readResource(uri: String) async throws -> MCPResourceContent {
        try ensureInitialized()

        let params: [String: AnyCodable] = [
            "uri": AnyCodable(uri),
        ]

        let response = try await sendRequest(method: "resources/read", params: params)

        guard let result = response.result else {
            if let error = response.error { throw error }
            throw MCPClientError.resourceReadFailed(uri)
        }

        let readResult = try decodeFromAnyCodable(MCPResourceReadResult.self, from: result)
        let first = readResult.contents.first
        return MCPResourceContent(
            uri: first?.uri ?? uri,
            text: first?.text,
            blob: first?.blob,
            mimeType: first?.mimeType
        )
    }

    /// Access the server notifications stream.
    public nonisolated func notifications() -> AsyncThrowingStream<MCPNotification, Error> {
        transport.notifications()
    }

    /// Whether the client has completed initialization.
    public var initialized: Bool { isInitialized }

    /// The server's declared capabilities, available after initialization.
    public var capabilities: MCPServerCapabilities? { serverCapabilities }

    // MARK: - Private Helpers

    private func nextRequestId() -> Int {
        let id = nextId
        nextId += 1
        return id
    }

    private func sendRequest(method: String, params: [String: AnyCodable]? = nil) async throws -> MCPResponse {
        let request = MCPRequest(id: nextRequestId(), method: method, params: params)
        return try await transport.send(request)
    }

    private func ensureInitialized() throws {
        guard isInitialized else {
            throw MCPClientError.notInitialized
        }
    }

    private func decodeFromAnyCodable<T: Decodable>(_ type: T.Type, from value: AnyCodable) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func schemaToJSON(_ value: AnyCodable) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func parseToolResult(_ result: AnyCodable) -> MCPToolResult {
        guard let dict = result.value as? [String: Any] else {
            return MCPToolResult(content: [.text(String(describing: result.value))], isError: false)
        }

        let isError = dict["isError"] as? Bool ?? false
        var contents: [MCPContent] = []

        if let contentArray = dict["content"] as? [[String: Any]] {
            for item in contentArray {
                let type = item["type"] as? String ?? "text"
                switch type {
                case "text":
                    if let text = item["text"] as? String {
                        contents.append(.text(text))
                    }
                case "image":
                    if let data = item["data"] as? String,
                       let mimeType = item["mimeType"] as? String {
                        contents.append(.image(data: data, mimeType: mimeType))
                    }
                case "resource":
                    if let resource = item["resource"] as? [String: Any],
                       let uri = resource["uri"] as? String,
                       let text = resource["text"] as? String {
                        contents.append(.resource(uri: uri, text: text))
                    }
                default:
                    if let text = item["text"] as? String {
                        contents.append(.text(text))
                    }
                }
            }
        }

        if contents.isEmpty {
            // Fallback: try to extract text from the result dict directly
            if let text = dict["text"] as? String {
                contents.append(.text(text))
            }
        }

        return MCPToolResult(content: contents, isError: isError)
    }
}

// MARK: - Internal Response Types

private struct MCPInitializeResult: Codable {
    let protocolVersion: String?
    let capabilities: MCPServerCapabilities
    let serverInfo: MCPServerInfo?
}

private struct MCPServerInfo: Codable {
    let name: String
    let version: String?
}

private struct MCPToolListResult: Codable {
    let tools: [MCPToolEntry]
}

private struct MCPToolEntry: Codable {
    let name: String
    let description: String?
    let inputSchema: AnyCodable?
}

private struct MCPResourceListResult: Codable {
    let resources: [MCPResource]
}

private struct MCPResourceReadResult: Codable {
    let contents: [MCPResourceContentEntry]
}

private struct MCPResourceContentEntry: Codable {
    let uri: String
    let text: String?
    let blob: String?
    let mimeType: String?
}

// MARK: - Client Errors

public enum MCPClientError: Error, Sendable, LocalizedError {
    case notInitialized
    case initializeFailed(String)
    case resourceReadFailed(String)
    case toolCallFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return AppLocalization.string("errors.mcp.client_not_initialized")
        case .initializeFailed(let reason):
            return AppLocalization.format("errors.mcp.initialize_failed_format", locale: .autoupdatingCurrent,
                reason
            )
        case .resourceReadFailed(let uri):
            return AppLocalization.format("errors.mcp.resource_read_failed_format", locale: .autoupdatingCurrent,
                uri
            )
        case .toolCallFailed(let reason):
            return AppLocalization.format("errors.mcp.tool_call_failed_format", locale: .autoupdatingCurrent,
                reason
            )
        }
    }
}
