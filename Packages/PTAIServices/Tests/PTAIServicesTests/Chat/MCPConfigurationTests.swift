import XCTest
@testable import PTAIServices

final class MCPConfigurationTests: XCTestCase {

    func testServerConfigCodable() throws {
        let tool = MCPToolInfo(name: "test_tool", description: "A test tool", parametersSchema: "{}")
        let config = MCPServerConfig(
            name: "Test Server",
            url: "http://localhost:8080",
            apiKey: "secret",
            isEnabled: true,
            discoveredTools: [tool]
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPServerConfig.self, from: data)

        XCTAssertEqual(decoded.name, "Test Server")
        XCTAssertEqual(decoded.url, "http://localhost:8080")
        XCTAssertEqual(decoded.apiKey, "secret")
        XCTAssertTrue(decoded.isEnabled)
        XCTAssertEqual(decoded.discoveredTools.count, 1)
        XCTAssertEqual(decoded.discoveredTools.first?.name, "test_tool")
    }

    func testConnectionStatusDisplay() {
        XCTAssertEqual(MCPConnectionStatus.disconnected.displayText, AppLocalization.string("common.disconnected"))
        XCTAssertEqual(MCPConnectionStatus.connecting.displayText, AppLocalization.string("common.connecting_ellipsis"))
        XCTAssertEqual(
            MCPConnectionStatus.connected(toolCount: 5).displayText,
            AppLocalization.format("common.connected_tool_count_format", locale: .autoupdatingCurrent, 5)
        )
        XCTAssertTrue(MCPConnectionStatus.error("fail").displayText.contains("fail"))
    }

    func testConnectionStatusIsConnected() {
        XCTAssertFalse(MCPConnectionStatus.disconnected.isConnected)
        XCTAssertFalse(MCPConnectionStatus.connecting.isConnected)
        XCTAssertTrue(MCPConnectionStatus.connected(toolCount: 3).isConnected)
        XCTAssertFalse(MCPConnectionStatus.error("x").isConnected)
    }

    func testConfigStore() {
        let suiteName = "MCPConfigTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = MCPConfigStore(defaults: defaults)

        // Initially empty
        XCTAssertTrue(store.loadConfigs().isEmpty)

        // Save and reload
        let configs = [
            MCPServerConfig(name: "Server A", url: "http://a.com"),
            MCPServerConfig(name: "Server B", url: "http://b.com"),
        ]
        store.saveConfigs(configs)

        let loaded = store.loadConfigs()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "Server A")
        XCTAssertEqual(loaded[1].name, "Server B")

        defaults.removePersistentDomain(forName: suiteName)
    }
}
