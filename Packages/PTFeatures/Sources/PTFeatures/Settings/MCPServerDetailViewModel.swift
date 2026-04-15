import Foundation
import Observation
import PTAIServices
import PTCore

public struct MCPToolSummary: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let parametersJSON: String?

    public init(id: String, name: String, description: String?, parametersJSON: String?) {
        self.id = id
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }
}

/// Abstraction over `MCPClient` + transport wiring, so tests can stub smoke-test behavior
/// without standing up a real network or process transport.
public protocol MCPToolsClientProtocol: Sendable {
    func connectAndListTools(for config: MCPServerConfig) async throws -> [MCPToolSummary]
    func callTool(config: MCPServerConfig, name: String, arguments: [String: Any]) async throws -> String
}

public struct LiveMCPToolsClient: MCPToolsClientProtocol {
    public init() {}

    public func connectAndListTools(for config: MCPServerConfig) async throws -> [MCPToolSummary] {
        let transport = try Self.makeTransport(for: config)
        let client = MCPClient(transport: transport)
        _ = try await client.initialize()
        let tools = try await client.listTools()
        try? await client.shutdown()
        return tools.map {
            MCPToolSummary(
                id: $0.name,
                name: $0.name,
                description: $0.description.isEmpty ? nil : $0.description,
                parametersJSON: $0.parametersSchema
            )
        }
    }

    public func callTool(config: MCPServerConfig, name: String, arguments: [String: Any]) async throws -> String {
        let transport = try Self.makeTransport(for: config)
        let client = MCPClient(transport: transport)
        _ = try await client.initialize()
        let result = try await client.callTool(name: name, arguments: arguments)
        try? await client.shutdown()
        if result.isError {
            throw MCPClientError.toolCallFailed(result.textContent)
        }
        return result.textContent
    }

    private static func makeTransport(for config: MCPServerConfig) throws -> any MCPTransport {
        guard let url = URL(string: config.url) else {
            throw MCPClientError.initializeFailed(
                AppLocalization.string("errors.url.invalid")
            )
        }
        return MCPHTTPSSETransport(serverURL: url, apiKey: config.apiKey)
    }
}

@MainActor
@Observable
public final class MCPServerDetailViewModel {
    public private(set) var draft: MCPServerConfig
    public private(set) var isNew: Bool
    public private(set) var isConnecting: Bool
    public private(set) var connectionError: String?
    public private(set) var tools: [MCPToolSummary]
    public private(set) var lastConnectionAttempt: Date?
    public private(set) var toolRunResult: String?
    public private(set) var toolRunError: String?
    public private(set) var isSaved: Bool

    private let store: MCPServerStore
    private let client: any MCPToolsClientProtocol

    public init(
        store: MCPServerStore,
        client: any MCPToolsClientProtocol = LiveMCPToolsClient()
    ) {
        self.store = store
        self.client = client
        self.draft = MCPServerConfig(name: "", url: "")
        self.isNew = true
        self.isConnecting = false
        self.connectionError = nil
        self.tools = []
        self.lastConnectionAttempt = nil
        self.toolRunResult = nil
        self.toolRunError = nil
        self.isSaved = false
    }

    public func load(serverId: String?) async {
        guard let serverId else {
            draft = MCPServerConfig(name: "", url: "")
            isNew = true
            isSaved = false
            return
        }
        let all = await store.load()
        if let existing = all.first(where: { $0.id == serverId }) {
            draft = existing
            isNew = false
            isSaved = true
        } else {
            draft = MCPServerConfig(name: "", url: "")
            isNew = true
            isSaved = false
        }
    }

    public func updateName(_ value: String) { draft.name = value }
    public func updateURL(_ value: String) { draft.url = value }
    public func updateAPIKey(_ value: String) { draft.apiKey = value.isEmpty ? nil : value }
    public func updateEnabled(_ value: Bool) { draft.isEnabled = value }
    public func updateTransport(_ value: MCPTransportType) { draft.transportType = value }
    public func updateCommand(_ value: String) { draft.command = value.isEmpty ? nil : value }
    public func updateArguments(_ value: [String]) { draft.arguments = value }
    public func updateEnvironment(_ value: [String: String]) { draft.environment = value }
    public func updateCustomHeaders(_ value: [String: String]) { draft.customHeaders = value }

    public enum SaveError: Error, Equatable {
        case invalidName
        case invalidURL
        case invalidCommand
    }

    public func save() async throws {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            connectionError = AppLocalization.string("settings.mcp.validation.name_required")
            throw SaveError.invalidName
        }
        draft.name = trimmedName

        switch draft.transportType {
        case .httpSSE:
            let trimmedURL = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedURL.isEmpty else {
                connectionError = AppLocalization.string("settings.mcp.validation.url_required")
                throw SaveError.invalidURL
            }
            draft.url = trimmedURL
        case .stdio:
            let command = (draft.command ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else {
                connectionError = AppLocalization.string("settings.mcp.validation.command_required")
                throw SaveError.invalidCommand
            }
            draft.command = command
        }

        connectionError = nil

        if isNew {
            try await store.add(draft)
            isNew = false
        } else {
            try await store.update(id: draft.id, draft)
        }
        isSaved = true
    }

    public func connectAndListTools() async {
        isConnecting = true
        connectionError = nil
        lastConnectionAttempt = Date()
        defer { isConnecting = false }
        do {
            let discovered = try await client.connectAndListTools(for: draft)
            tools = discovered
        } catch {
            tools = []
            connectionError = AppLocalization.localizedErrorDescription(error)
                ?? error.localizedDescription
        }
    }

    public func runTool(name: String, argumentsJSON: String) async {
        toolRunResult = nil
        toolRunError = nil
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        var arguments: [String: Any] = [:]
        if !trimmed.isEmpty {
            guard let data = trimmed.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                toolRunError = AppLocalization.string("settings.mcp.tools.run_sheet.invalid_json")
                return
            }
            arguments = parsed
        }
        do {
            let text = try await client.callTool(config: draft, name: name, arguments: arguments)
            toolRunResult = text
        } catch {
            toolRunError = AppLocalization.localizedErrorDescription(error)
                ?? error.localizedDescription
        }
    }

    public func clearToolRunResult() {
        toolRunResult = nil
        toolRunError = nil
    }
}
