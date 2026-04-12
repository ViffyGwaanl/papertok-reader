import XCTest
@testable import PTAIServices

final class MCPClientTests: XCTestCase {

    // MARK: - Message Serialization

    func testMCPRequestEncoding() throws {
        let request = MCPRequest(id: 1, method: "initialize", params: [
            "protocolVersion": AnyCodable("2024-11-05"),
        ])

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["id"] as? Int, 1)
        XCTAssertEqual(json["method"] as? String, "initialize")
        let params = json["params"] as? [String: Any]
        XCTAssertEqual(params?["protocolVersion"] as? String, "2024-11-05")
    }

    func testMCPResponseDecoding() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": 1,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": { "listChanged": true }
                },
                "serverInfo": { "name": "test-server", "version": "1.0" }
            }
        }
        """

        let response = try JSONDecoder().decode(MCPResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 1)
        XCTAssertNil(response.error)
        XCTAssertNotNil(response.result)
    }

    func testMCPErrorResponseDecoding() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": 2,
            "error": {
                "code": -32601,
                "message": "Method not found"
            }
        }
        """

        let response = try JSONDecoder().decode(MCPResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.id, 2)
        XCTAssertNil(response.result)
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, MCPError.methodNotFound)
        XCTAssertEqual(response.error?.message, "Method not found")
    }

    func testMCPNotificationEncoding() throws {
        let notification = MCPNotification(method: "notifications/initialized")

        let data = try JSONEncoder().encode(notification)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["method"] as? String, "notifications/initialized")
    }

    func testAnyCodableRoundTrip() throws {
        let original = AnyCodable([
            "string": "hello",
            "number": 42,
            "bool": true,
            "nested": ["key": "value"],
        ] as [String: Any])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testAnyCodableNullHandling() throws {
        let json = "null"
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(decoded.value is NSNull)
    }

    // MARK: - MCPClient Initialize Flow

    func testInitializeFlow() async throws {
        let transport = MockMCPTransport()

        // Set up initialize response
        transport.responseHandler = { request in
            if request.method == "initialize" {
                return MCPResponse(
                    id: request.id,
                    result: AnyCodable([
                        "protocolVersion": "2024-11-05",
                        "capabilities": [
                            "tools": ["listChanged": true],
                        ] as [String: Any],
                        "serverInfo": [
                            "name": "test-server",
                            "version": "1.0",
                        ] as [String: Any],
                    ] as [String: Any])
                )
            }
            return MCPResponse(id: request.id)
        }

        let client = MCPClient(transport: transport)
        let capabilities = try await client.initialize()

        XCTAssertNotNil(capabilities.tools)
        XCTAssertEqual(capabilities.tools?.listChanged, true)
        let isInit = await client.initialized
        XCTAssertTrue(isInit)
        XCTAssertTrue(transport.connectCalled)
    }

    // MARK: - Tool Listing

    func testListTools() async throws {
        let transport = MockMCPTransport()

        transport.responseHandler = { request in
            switch request.method {
            case "initialize":
                return MCPResponse(
                    id: request.id,
                    result: AnyCodable([
                        "protocolVersion": "2024-11-05",
                        "capabilities": [String: Any](),
                    ] as [String: Any])
                )
            case "tools/list":
                return MCPResponse(
                    id: request.id,
                    result: AnyCodable([
                        "tools": [
                            [
                                "name": "search",
                                "description": "Search documents",
                                "inputSchema": [
                                    "type": "object",
                                    "properties": [
                                        "query": ["type": "string", "description": "Search query"],
                                    ] as [String: Any],
                                ] as [String: Any],
                            ] as [String: Any],
                            [
                                "name": "summarize",
                                "description": "Summarize text",
                            ] as [String: Any],
                        ] as [[String: Any]],
                    ] as [String: Any])
                )
            default:
                return MCPResponse(id: request.id)
            }
        }

        let client = MCPClient(transport: transport)
        try await client.initialize()
        let tools = try await client.listTools()

        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools[0].name, "search")
        XCTAssertEqual(tools[0].description, "Search documents")
        XCTAssertNotNil(tools[0].parametersSchema)
        XCTAssertEqual(tools[1].name, "summarize")
    }

    // MARK: - Not Initialized Guard

    func testCallToolWithoutInitializeFails() async {
        let transport = MockMCPTransport()
        let client = MCPClient(transport: transport)

        do {
            _ = try await client.callTool(name: "test")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is MCPClientError)
        }
    }

    // MARK: - Tool Execution

    func testCallTool() async throws {
        let transport = MockMCPTransport()

        transport.responseHandler = { request in
            switch request.method {
            case "initialize":
                return MCPResponse(
                    id: request.id,
                    result: AnyCodable([
                        "protocolVersion": "2024-11-05",
                        "capabilities": [String: Any](),
                    ] as [String: Any])
                )
            case "tools/call":
                return MCPResponse(
                    id: request.id,
                    result: AnyCodable([
                        "content": [
                            ["type": "text", "text": "Found 3 results"] as [String: Any],
                        ] as [[String: Any]],
                    ] as [String: Any])
                )
            default:
                return MCPResponse(id: request.id)
            }
        }

        let client = MCPClient(transport: transport)
        try await client.initialize()
        let result = try await client.callTool(name: "search", arguments: ["query": "swift"])

        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.textContent, "Found 3 results")
    }

    // MARK: - MCPTransportType

    func testTransportTypeCodable() throws {
        let config = MCPServerConfig(
            name: "test",
            url: "https://example.com",
            transportType: .httpSSE
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPServerConfig.self, from: data)

        XCTAssertEqual(decoded.transportType, .httpSSE)
    }

    func testTransportTypeStdioCodable() throws {
        let config = MCPServerConfig(
            name: "local",
            url: "/usr/local/bin/mcp-server",
            transportType: .stdio
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPServerConfig.self, from: data)

        XCTAssertEqual(decoded.transportType, .stdio)
    }
}

// MARK: - Mock Transport

final class MockMCPTransport: MCPTransport, @unchecked Sendable {
    var connectCalled = false
    var disconnectCalled = false
    var sentRequests: [MCPRequest] = []
    var responseHandler: ((MCPRequest) -> MCPResponse)?

    func connect() async throws {
        connectCalled = true
    }

    func disconnect() async throws {
        disconnectCalled = true
    }

    func send(_ request: MCPRequest) async throws -> MCPResponse {
        sentRequests.append(request)
        return responseHandler?(request) ?? MCPResponse(id: request.id)
    }

    func notifications() -> AsyncThrowingStream<MCPNotification, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
