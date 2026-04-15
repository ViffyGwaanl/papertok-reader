import XCTest
@testable import PTAIServices

final class MCPConfigurationTests: XCTestCase {

    func testServerConfigCodableDropsSecrets() throws {
        let tool = MCPToolInfo(name: "test_tool", description: "A test tool", parametersSchema: "{}")
        let config = MCPServerConfig(
            name: "Test Server",
            url: "http://localhost:8080",
            apiKey: "secret",
            isEnabled: true,
            discoveredTools: [tool],
            customHeaders: ["X-Header": "value"]
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPServerConfig.self, from: data)

        XCTAssertEqual(decoded.name, "Test Server")
        XCTAssertEqual(decoded.url, "http://localhost:8080")
        XCTAssertNil(decoded.apiKey, "apiKey must not be persisted in JSON")
        XCTAssertTrue(decoded.customHeaders.isEmpty, "customHeaders must not be persisted in JSON")
        XCTAssertTrue(decoded.isEnabled)
        XCTAssertEqual(decoded.discoveredTools.count, 1)
        XCTAssertEqual(decoded.discoveredTools.first?.name, "test_tool")

        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("secret"))
        XCTAssertFalse(json.contains("X-Header"))
    }

    func testServerConfigDecodesLegacyPayloadWithoutNewFields() throws {
        let legacyJSON = """
        {"id":"abc","name":"N","url":"http://x","isEnabled":true,"transportType":"http_sse","discoveredTools":[]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MCPServerConfig.self, from: legacyJSON)
        XCTAssertEqual(decoded.id, "abc")
        XCTAssertEqual(decoded.arguments, [])
        XCTAssertTrue(decoded.environment.isEmpty)
        XCTAssertNil(decoded.command)
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

}
