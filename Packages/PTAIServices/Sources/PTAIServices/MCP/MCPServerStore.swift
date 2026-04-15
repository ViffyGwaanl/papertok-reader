import Foundation
import PTCore

/// Persistence actor for MCP server configurations.
///
/// - Non-secret fields are written as JSON to `<directory>/servers.json` (atomic writes).
/// - Secrets (`apiKey`, `customHeaders`) are persisted to Keychain keyed by server id and
///   are never encoded into the on-disk JSON. A regression test enforces this invariant.
/// - A one-shot migrator pulls legacy `UserDefaults` payloads (`mcp_server_configs`) forward.
public actor MCPServerStore {
    private let directory: URL
    private let fileURL: URL
    private let keychain: KeychainServing
    private let defaults: UserDefaults

    private static let legacyDefaultsKey = "mcp_server_configs"
    private static let migrationMarkerKey = "papertok.mcp.migrated_v2"

    public init(
        directory: URL? = nil,
        keychain: KeychainServing = SystemKeychainService.shared,
        defaults: UserDefaults = .standard
    ) {
        let resolved: URL
        if let directory {
            resolved = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            resolved = base.appendingPathComponent("papertok/mcp/", isDirectory: true)
        }
        self.directory = resolved
        self.fileURL = resolved.appendingPathComponent("servers.json")
        self.keychain = keychain
        self.defaults = defaults
    }

    // MARK: - Public API

    public func load() async -> [MCPServerConfig] {
        await migrateLegacyIfNeeded()
        return readFromDisk()
    }

    public func save(_ servers: [MCPServerConfig]) async throws {
        try writeToDisk(servers)
        for server in servers {
            try writeSecrets(for: server)
        }
    }

    public func add(_ server: MCPServerConfig) async throws {
        var current = readFromDisk()
        current.append(server)
        try await save(current)
    }

    public func remove(id: String) async throws {
        var current = readFromDisk()
        current.removeAll { $0.id == id }
        try await save(current)
        try? keychain.delete(forKey: apiKeyKeychainKey(for: id))
        try? keychain.delete(forKey: headersKeychainKey(for: id))
    }

    public func update(id: String, _ newValue: MCPServerConfig) async throws {
        var current = readFromDisk()
        guard let idx = current.firstIndex(where: { $0.id == id }) else { return }
        current[idx] = newValue
        try await save(current)
    }

    public func migrateLegacyIfNeeded() async {
        if defaults.bool(forKey: Self.migrationMarkerKey) { return }
        guard let data = defaults.data(forKey: Self.legacyDefaultsKey) else {
            defaults.set(true, forKey: Self.migrationMarkerKey)
            return
        }
        // Legacy shape included `apiKey` inside the JSON payload. Decode via legacy model,
        // then forward through the new store so secrets land in Keychain.
        let legacy = (try? JSONDecoder().decode([LegacyMCPServerConfig].self, from: data)) ?? []
        let migrated = legacy.map { $0.upgraded() }
        if !migrated.isEmpty {
            try? writeToDisk(migrated)
            for server in migrated {
                try? writeSecrets(for: server)
            }
        }
        defaults.removeObject(forKey: Self.legacyDefaultsKey)
        defaults.set(true, forKey: Self.migrationMarkerKey)
    }

    // MARK: - Disk I/O

    private func readFromDisk() -> [MCPServerConfig] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        do {
            var servers = try decoder.decode([MCPServerConfig].self, from: data)
            for i in servers.indices {
                servers[i].apiKey = keychain.load(forKey: apiKeyKeychainKey(for: servers[i].id))
                if let headerJSON = keychain.load(forKey: headersKeychainKey(for: servers[i].id)),
                   let headerData = headerJSON.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([String: String].self, from: headerData) {
                    servers[i].customHeaders = decoded
                }
            }
            return servers
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return []
        }
    }

    private func writeToDisk(_ servers: [MCPServerConfig]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(servers)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func writeSecrets(for server: MCPServerConfig) throws {
        let apiKeyKey = apiKeyKeychainKey(for: server.id)
        if let apiKey = server.apiKey, !apiKey.isEmpty {
            try keychain.save(apiKey, forKey: apiKeyKey)
        } else {
            try? keychain.delete(forKey: apiKeyKey)
        }

        let headersKey = headersKeychainKey(for: server.id)
        if server.customHeaders.isEmpty {
            try? keychain.delete(forKey: headersKey)
        } else {
            let data = try JSONEncoder().encode(server.customHeaders)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            try keychain.save(json, forKey: headersKey)
        }
    }

    private func apiKeyKeychainKey(for id: String) -> String {
        "papertok.mcp.\(id).api_key"
    }

    private func headersKeychainKey(for id: String) -> String {
        "papertok.mcp.\(id).custom_headers"
    }
}

// MARK: - Legacy payload

private struct LegacyMCPServerConfig: Decodable {
    let id: String
    let name: String
    let url: String
    let apiKey: String?
    let isEnabled: Bool?
    let transportType: MCPTransportType?
    let discoveredTools: [MCPToolInfo]?

    func upgraded() -> MCPServerConfig {
        MCPServerConfig(
            id: id,
            name: name,
            url: url,
            apiKey: apiKey,
            isEnabled: isEnabled ?? true,
            transportType: transportType ?? .httpSSE,
            discoveredTools: discoveredTools ?? []
        )
    }
}
