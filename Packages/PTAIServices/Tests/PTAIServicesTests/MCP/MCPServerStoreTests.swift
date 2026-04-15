import XCTest
import PTCore
@testable import PTAIServices

final class InMemoryKeychain: KeychainServing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "InMemoryKeychain")
    private var storage: [String: String] = [:]

    func save(_ value: String, forKey key: String) throws {
        queue.sync { storage[key] = value }
    }

    func load(forKey key: String) -> String? {
        queue.sync { storage[key] }
    }

    func delete(forKey key: String) throws {
        queue.sync { _ = storage.removeValue(forKey: key) }
    }

    func snapshot() -> [String: String] {
        queue.sync { storage }
    }
}

final class MCPServerStoreTests: XCTestCase {
    private var tempDir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var keychain: InMemoryKeychain!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MCPServerStoreTests-\(UUID().uuidString)", isDirectory: true)
        suiteName = "MCPServerStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        keychain = InMemoryKeychain()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore() -> MCPServerStore {
        MCPServerStore(directory: tempDir, keychain: keychain, defaults: defaults)
    }

    // MARK: - A. Round-trip

    func testSaveAndLoadRoundTripThroughJSONFile() async throws {
        let store = makeStore()
        let server = MCPServerConfig(
            name: "Alpha",
            url: "https://alpha.example.com",
            apiKey: "sk-alpha",
            transportType: .httpSSE,
            customHeaders: ["X-Auth": "token"]
        )
        try await store.save([server])

        let reloaded = await store.load()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded[0].name, "Alpha")
        XCTAssertEqual(reloaded[0].apiKey, "sk-alpha")
        XCTAssertEqual(reloaded[0].customHeaders, ["X-Auth": "token"])
    }

    // MARK: - B. Add

    func testAddAppendsServer() async throws {
        let store = makeStore()
        try await store.add(MCPServerConfig(name: "A", url: "http://a"))
        try await store.add(MCPServerConfig(name: "B", url: "http://b"))
        let result = await store.load()
        XCTAssertEqual(result.map(\.name), ["A", "B"])
    }

    // MARK: - C. Remove + Keychain cleanup

    func testRemoveDeletesServerAndKeychainSecrets() async throws {
        let store = makeStore()
        let server = MCPServerConfig(
            id: "srv-1",
            name: "N",
            url: "http://x",
            apiKey: "key-123",
            customHeaders: ["A": "B"]
        )
        try await store.save([server])
        XCTAssertNotNil(keychain.load(forKey: "papertok.mcp.srv-1.api_key"))
        XCTAssertNotNil(keychain.load(forKey: "papertok.mcp.srv-1.custom_headers"))

        try await store.remove(id: "srv-1")

        let result = await store.load()
        XCTAssertTrue(result.isEmpty)
        XCTAssertNil(keychain.load(forKey: "papertok.mcp.srv-1.api_key"))
        XCTAssertNil(keychain.load(forKey: "papertok.mcp.srv-1.custom_headers"))
    }

    // MARK: - D. Update

    func testUpdateChangesStoredFields() async throws {
        let store = makeStore()
        let server = MCPServerConfig(id: "u-1", name: "Old", url: "http://old", apiKey: "old-key")
        try await store.save([server])

        var updated = server
        updated.name = "New"
        updated.url = "http://new"
        updated.apiKey = "new-key"
        try await store.update(id: "u-1", updated)

        let result = await store.load()
        XCTAssertEqual(result.first?.name, "New")
        XCTAssertEqual(result.first?.url, "http://new")
        XCTAssertEqual(result.first?.apiKey, "new-key")
    }

    // MARK: - E. Secrets never in JSON

    func testSecretsNeverPersistedInJSONFile() async throws {
        let store = makeStore()
        let server = MCPServerConfig(
            name: "S",
            url: "http://s",
            apiKey: "SUPER_SECRET_KEY",
            customHeaders: ["X-Secret": "HEADER_VALUE_XYZ"]
        )
        try await store.save([server])

        let fileURL = tempDir.appendingPathComponent("servers.json")
        let data = try Data(contentsOf: fileURL)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("SUPER_SECRET_KEY"))
        XCTAssertFalse(json.contains("HEADER_VALUE_XYZ"))
        XCTAssertFalse(json.contains("apiKey"))
        XCTAssertFalse(json.contains("customHeaders"))
    }

    // MARK: - F. Legacy migration

    func testLegacyUserDefaultsMigratesToJSONPlusKeychain() async throws {
        let legacy = """
        [{"id":"legacy-1","name":"Legacy","url":"http://legacy","apiKey":"legacy-key","isEnabled":true,"transportType":"http_sse","discoveredTools":[]}]
        """.data(using: .utf8)!
        defaults.set(legacy, forKey: "mcp_server_configs")

        let store = makeStore()
        let result = await store.load()

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "legacy-1")
        XCTAssertEqual(result[0].apiKey, "legacy-key")

        let fileURL = tempDir.appendingPathComponent("servers.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(keychain.load(forKey: "papertok.mcp.legacy-1.api_key"), "legacy-key")
        XCTAssertNil(defaults.data(forKey: "mcp_server_configs"))
        XCTAssertTrue(defaults.bool(forKey: "papertok.mcp.migrated_v2"))
    }

    func testMigrationIsIdempotent() async throws {
        let legacy = """
        [{"id":"x","name":"X","url":"http://x","apiKey":"k","isEnabled":true,"transportType":"http_sse","discoveredTools":[]}]
        """.data(using: .utf8)!
        defaults.set(legacy, forKey: "mcp_server_configs")

        let store = makeStore()
        _ = await store.load()

        // Second run should not re-populate from UserDefaults even if we re-set the key.
        defaults.set(legacy, forKey: "mcp_server_configs")
        await store.migrateLegacyIfNeeded()

        // Since marker is set, the legacy key should still be there (untouched by a re-run).
        XCTAssertNotNil(defaults.data(forKey: "mcp_server_configs"))
        XCTAssertTrue(defaults.bool(forKey: "papertok.mcp.migrated_v2"))
    }

    // MARK: - G. Corrupted JSON

    func testCorruptedJSONFileReturnsEmptyList() async throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("servers.json")
        try Data("not valid json".utf8).write(to: fileURL)

        let store = makeStore()
        let result = await store.load()
        XCTAssertTrue(result.isEmpty)
    }
}
