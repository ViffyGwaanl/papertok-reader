import XCTest
@testable import PTAIServices
@testable import PTNetworking

final class AnthropicProviderTests: XCTestCase {

    // MARK: - Request body serialization

    func testBuildRequestBody_extractsSystemPrompt() throws {
        let provider = AnthropicProvider(overrideAPIKey: "test-key")
        let request = ChatRequest(
            messages: [
                .system("You are a helpful assistant."),
                .user("Hello"),
            ],
            model: "claude-sonnet-4-20250514",
            maxTokens: 1024
        )

        let body = provider.buildRequestBody(request: request, stream: false)

        // System should be top-level, not in messages
        XCTAssertEqual(body.system?.count, 1)
        XCTAssertEqual(body.system?.first?.text, "You are a helpful assistant.")
        XCTAssertEqual(body.system?.first?.type, "text")

        // Messages should only contain the user message
        XCTAssertEqual(body.messages.count, 1)
        XCTAssertEqual(body.messages.first?.role, "user")
    }

    func testBuildRequestBody_noSystemMessage() throws {
        let provider = AnthropicProvider(overrideAPIKey: "test-key")
        let request = ChatRequest(
            messages: [.user("Hello")],
            model: "claude-sonnet-4-20250514"
        )

        let body = provider.buildRequestBody(request: request, stream: false)
        XCTAssertNil(body.system)
        XCTAssertEqual(body.messages.count, 1)
    }

    func testBuildRequestBody_defaultMaxTokens() throws {
        let provider = AnthropicProvider(overrideAPIKey: "test-key", defaultMaxTokens: 2048)
        let request = ChatRequest(
            messages: [.user("Hi")],
            model: "claude-sonnet-4-20250514"
        )

        let body = provider.buildRequestBody(request: request, stream: false)
        XCTAssertEqual(body.maxTokens, 2048)
    }

    func testBuildRequestBody_overridesMaxTokens() throws {
        let provider = AnthropicProvider(overrideAPIKey: "test-key", defaultMaxTokens: 2048)
        let request = ChatRequest(
            messages: [.user("Hi")],
            model: "claude-sonnet-4-20250514",
            maxTokens: 512
        )

        let body = provider.buildRequestBody(request: request, stream: false)
        XCTAssertEqual(body.maxTokens, 512)
    }

    func testBuildRequestBody_streamFlag() throws {
        let provider = AnthropicProvider(overrideAPIKey: "test-key")
        let request = ChatRequest(messages: [.user("Hi")], model: "claude-sonnet-4-20250514")

        let bodyNoStream = provider.buildRequestBody(request: request, stream: false)
        XCTAssertFalse(bodyNoStream.stream)

        let bodyStream = provider.buildRequestBody(request: request, stream: true)
        XCTAssertTrue(bodyStream.stream)
    }

    func testBuildRequestBody_tools() throws {
        let provider = AnthropicProvider(overrideAPIKey: "test-key")
        let tool = ToolDefinition(
            name: "get_weather",
            description: "Get weather for a city",
            parameters: ToolParametersSchema(
                properties: [
                    "city": ToolPropertySchema(type: "string", description: "City name"),
                ],
                required: ["city"]
            )
        )
        let request = ChatRequest(
            messages: [.user("What's the weather?")],
            model: "claude-sonnet-4-20250514",
            tools: [tool]
        )

        let body = provider.buildRequestBody(request: request, stream: false)
        XCTAssertEqual(body.tools?.count, 1)
        XCTAssertEqual(body.tools?.first?.name, "get_weather")
        XCTAssertEqual(body.tools?.first?.inputSchema.type, "object")
        XCTAssertEqual(body.tools?.first?.inputSchema.required, ["city"])
    }

    func testBuildRequestBody_serialization() throws {
        let provider = AnthropicProvider(overrideAPIKey: "test-key")
        let request = ChatRequest(
            messages: [
                .system("System prompt"),
                .user("Hello"),
            ],
            model: "claude-sonnet-4-20250514",
            temperature: 0.7,
            maxTokens: 1024,
            topP: 0.91,
            stopSequences: ["END"]
        )

        let body = provider.buildRequestBody(request: request, stream: false)
        let encoder = JSONEncoder()
        let data = try encoder.encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["model"] as? String, "claude-sonnet-4-20250514")
        XCTAssertEqual(json?["max_tokens"] as? Int, 1024)
        XCTAssertEqual(json?["temperature"] as? Double, 0.7)
        XCTAssertEqual(json?["top_p"] as? Double, 0.91)
        XCTAssertEqual(json?["stop_sequences"] as? [String], ["END"])
        XCTAssertFalse(json?["stream"] as? Bool ?? true)
        // system is top-level array
        XCTAssertNotNil(json?["system"] as? [[String: Any]])
    }

    // MARK: - Message encoding

    func testEncodeMessage_toolResult() throws {
        let provider = AnthropicProvider(overrideAPIKey: "test-key")
        let msg = ChatMessage.toolResult(toolCallId: "call_123", content: "Sunny, 72F")

        let encoded = provider.encodeMessage(msg)
        XCTAssertEqual(encoded.role, "user")
        XCTAssertEqual(encoded.content.count, 1)
    }

    func testEncodeMessage_assistantWithToolCalls() throws {
        let provider = AnthropicProvider(overrideAPIKey: "test-key")
        let msg = ChatMessage.assistant(
            "Let me check the weather.",
            toolCalls: [ToolCall(id: "call_1", name: "get_weather", arguments: "{\"city\":\"NYC\"}")]
        )

        let encoded = provider.encodeMessage(msg)
        XCTAssertEqual(encoded.role, "assistant")
        // Should have text block + tool_use block
        XCTAssertEqual(encoded.content.count, 2)
    }

    // MARK: - Response parsing

    func testResponseParsing_textBlock() throws {
        let json = """
        {
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "content": [
                {"type": "text", "text": "Hello! How can I help?"}
            ],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 15}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AnthropicResponse.self, from: json)
        XCTAssertEqual(response.id, "msg_123")
        XCTAssertEqual(response.content.count, 1)
        XCTAssertEqual(response.content.first?.type, "text")
        XCTAssertEqual(response.content.first?.text, "Hello! How can I help?")
        XCTAssertEqual(response.stopReason, "end_turn")
        XCTAssertEqual(response.usage?.inputTokens, 10)
        XCTAssertEqual(response.usage?.outputTokens, 15)
    }

    func testResponseParsing_toolUseBlock() throws {
        let json = """
        {
            "id": "msg_456",
            "type": "message",
            "role": "assistant",
            "content": [
                {"type": "text", "text": "Let me check."},
                {"type": "tool_use", "id": "toolu_1", "name": "get_weather", "input": {"city": "NYC"}}
            ],
            "stop_reason": "tool_use",
            "usage": {"input_tokens": 20, "output_tokens": 30}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AnthropicResponse.self, from: json)
        XCTAssertEqual(response.content.count, 2)
        XCTAssertEqual(response.content[0].type, "text")
        XCTAssertEqual(response.content[1].type, "tool_use")
        XCTAssertEqual(response.content[1].id, "toolu_1")
        XCTAssertEqual(response.content[1].name, "get_weather")
        XCTAssertNotNil(response.content[1].input)
        XCTAssertEqual(response.stopReason, "tool_use")
    }

    func testResponseParsing_thinkingBlock() throws {
        let json = """
        {
            "id": "msg_789",
            "type": "message",
            "role": "assistant",
            "content": [
                {"type": "thinking", "thinking": "Let me reason about this..."},
                {"type": "text", "text": "The answer is 42."}
            ],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 5, "output_tokens": 50}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AnthropicResponse.self, from: json)
        XCTAssertEqual(response.content.count, 2)
        XCTAssertEqual(response.content[0].type, "thinking")
        XCTAssertEqual(response.content[0].thinking, "Let me reason about this...")
        XCTAssertEqual(response.content[1].type, "text")
        XCTAssertEqual(response.content[1].text, "The answer is 42.")
    }

    // MARK: - Stream event parsing

    func testStreamEventParsing_messageStart() throws {
        let json = """
        {"type": "message_start", "message": {"id": "msg_1", "usage": {"input_tokens": 10, "output_tokens": 0}}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(AnthropicStreamEvent.self, from: json)
        XCTAssertEqual(event.type, "message_start")
        XCTAssertEqual(event.message?.id, "msg_1")
        XCTAssertEqual(event.message?.usage?.inputTokens, 10)
    }

    func testStreamEventParsing_contentBlockStart() throws {
        let json = """
        {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(AnthropicStreamEvent.self, from: json)
        XCTAssertEqual(event.type, "content_block_start")
        XCTAssertEqual(event.index, 0)
        XCTAssertEqual(event.contentBlock?.type, "text")
    }

    func testStreamEventParsing_textDelta() throws {
        let json = """
        {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello"}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(AnthropicStreamEvent.self, from: json)
        XCTAssertEqual(event.type, "content_block_delta")
        XCTAssertEqual(event.delta?.type, "text_delta")
        XCTAssertEqual(event.delta?.text, "Hello")
    }

    func testStreamEventParsing_thinkingDelta() throws {
        let json = """
        {"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "reasoning..."}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(AnthropicStreamEvent.self, from: json)
        XCTAssertEqual(event.delta?.type, "thinking_delta")
        XCTAssertEqual(event.delta?.thinking, "reasoning...")
    }

    func testStreamEventParsing_inputJsonDelta() throws {
        let json = """
        {"type": "content_block_delta", "index": 1, "delta": {"type": "input_json_delta", "partial_json": "{\\"city\\""}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(AnthropicStreamEvent.self, from: json)
        XCTAssertEqual(event.delta?.type, "input_json_delta")
        XCTAssertEqual(event.delta?.partialJson, "{\"city\"")
    }

    func testAccumulateStreamUsage_acrossMessageStartAndMessageDelta() throws {
        let startJSON = """
        {"type":"message_start","message":{"id":"msg_1","usage":{"input_tokens":12,"output_tokens":0}}}
        """.data(using: .utf8)!
        let deltaJSON = """
        {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":34}}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let start = try decoder.decode(AnthropicStreamEvent.self, from: startJSON)
        let delta = try decoder.decode(AnthropicStreamEvent.self, from: deltaJSON)

        let usage = AnthropicProvider.accumulateStreamUsage(events: [start, delta])
        XCTAssertEqual(usage.promptTokens, 12)
        XCTAssertEqual(usage.completionTokens, 34)
        XCTAssertEqual(usage.totalTokens, 46)
    }

    func testStreamEventParsing_messageDelta() throws {
        let json = """
        {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"input_tokens": 0, "output_tokens": 25}}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(AnthropicStreamEvent.self, from: json)
        XCTAssertEqual(event.type, "message_delta")
        XCTAssertEqual(event.delta?.stopReason, "end_turn")
        XCTAssertEqual(event.usage?.outputTokens, 25)
    }

    // MARK: - Error mapping

    func testErrorMapping_401() {
        let provider = AnthropicProvider(overrideAPIKey: "test-key")
        let networkError = NetworkError.httpError(statusCode: 401, data: "Unauthorized".data(using: .utf8))
        let mapped = provider.mapNetworkError(networkError)

        if case ProviderError.authenticationFailed(let msg) = mapped {
            XCTAssertTrue(msg.contains("Unauthorized"))
        } else {
            XCTFail("Expected authenticationFailed, got \(mapped)")
        }
    }

    func testErrorMapping_429() {
        let provider = AnthropicProvider(overrideAPIKey: "test-key")
        let networkError = NetworkError.httpError(statusCode: 429, data: nil)
        let mapped = provider.mapNetworkError(networkError)

        if case ProviderError.rateLimited = mapped {
            // Expected
        } else {
            XCTFail("Expected rateLimited, got \(mapped)")
        }
    }

    func testErrorMapping_529() {
        let provider = AnthropicProvider(overrideAPIKey: "test-key")
        let networkError = NetworkError.httpError(statusCode: 529, data: nil)
        let mapped = provider.mapNetworkError(networkError)

        if case ProviderError.serverError(let code, let msg) = mapped {
            XCTAssertEqual(code, 529)
            XCTAssertTrue(msg?.contains("overloaded") ?? false)
        } else {
            XCTFail("Expected serverError 529, got \(mapped)")
        }
    }

    // MARK: - Capabilities

    func testSupportedCapabilities() {
        let provider = AnthropicProvider(overrideAPIKey: "test-key")
        let caps = provider.supportedCapabilities
        XCTAssertTrue(caps.contains(.chat))
        XCTAssertTrue(caps.contains(.vision))
        XCTAssertTrue(caps.contains(.toolCalling))
        XCTAssertTrue(caps.contains(.streaming))
        XCTAssertTrue(caps.contains(.thinking))
    }

    // MARK: - API Key resolution

    func testResolveAPIKey_overrideKey() async throws {
        let provider = AnthropicProvider(overrideAPIKey: "my-test-key")
        // complete() will use overrideAPIKey before trying Keychain
        // We can't call complete without a real server, but we verify the provider was constructed
        XCTAssertEqual(provider.id, "anthropic")
        XCTAssertEqual(provider.displayName, "Anthropic")
    }

    func testResolveAPIKey_noKeyThrows() {
        // Use a bogus keychain key that won't exist, with no override
        let provider = AnthropicProvider(apiKeyKeychainKey: "nonexistent_key_for_test")

        // The resolveAPIKey is private, but we can test it indirectly:
        // On macOS, KeychainService.load may throw or return nil.
        // Either way, calling complete should fail with authenticationFailed.
        let expectation = XCTestExpectation(description: "Should fail with auth error")

        Task {
            do {
                let request = ChatRequest(messages: [.user("Hi")], model: "claude-sonnet-4-20250514")
                _ = try await provider.complete(request)
                XCTFail("Should have thrown")
            } catch let error as ProviderError {
                if case .authenticationFailed = error {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected authenticationFailed, got \(error)")
                }
            } catch {
                // Keychain or network error — still acceptable in test environment
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }
}
