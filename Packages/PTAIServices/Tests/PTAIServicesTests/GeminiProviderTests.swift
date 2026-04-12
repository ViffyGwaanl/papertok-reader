import Foundation
import Testing
@testable import PTAIServices

@Suite("GeminiProvider")
struct GeminiProviderTests {

    @Test("Request body encodes system instruction and user contents")
    func requestBodyEncodesBasicChat() throws {
        let provider = GeminiProvider(overrideAPIKey: "test-key")
        let request = ChatRequest(
            messages: [
                .system("You are helpful."),
                .user("Hello")
            ],
            model: "gemini-2.0-flash-exp",
            temperature: 0.5,
            maxTokens: 256
        )

        let body = provider.buildRequestBody(request: request)
        #expect(body.contents.count == 1)
        #expect(body.contents.first?.role == "user")
        #expect(body.systemInstruction != nil)
        #expect(body.generationConfig?.temperature == 0.5)
        #expect(body.generationConfig?.maxOutputTokens == 256)

        let data = try JSONEncoder().encode(body)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("system_instruction"))
        #expect(json.contains("You are helpful."))
        #expect(json.contains("Hello"))
        #expect(json.contains("generation_config"))
        #expect(json.contains("max_output_tokens"))
    }

    @Test("Assistant messages map role to model")
    func assistantRoleMapsToModel() {
        let provider = GeminiProvider(overrideAPIKey: "test-key")
        let content = provider.encodeMessage(.assistant("Hi there"))
        #expect(content.role == "model")
    }

    @Test("Tool definitions encode as functionDeclarations")
    func toolsEncodeAsFunctionDeclarations() throws {
        let provider = GeminiProvider(overrideAPIKey: "test-key")
        let tool = ToolDefinition(
            name: "get_weather",
            description: "Get weather",
            parameters: ToolParametersSchema(
                properties: [
                    "city": ToolPropertySchema(type: "string", description: "City name")
                ],
                required: ["city"]
            )
        )
        let request = ChatRequest(
            messages: [.user("What's the weather?")],
            model: "gemini-2.0-flash-exp",
            tools: [tool]
        )
        let body = provider.buildRequestBody(request: request)
        #expect(body.tools?.count == 1)
        #expect(body.tools?.first?.functionDeclarations.first?.name == "get_weather")

        let data = try JSONEncoder().encode(body)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("function_declarations"))
        #expect(json.contains("get_weather"))
    }

    @Test("Inline base64 image encodes as inline_data")
    func imageEncodesAsInlineData() throws {
        let provider = GeminiProvider(overrideAPIKey: "test-key")
        let msg = ChatMessage(
            role: .user,
            content: [
                .text("Describe"),
                .imageBase64(data: "AAAA", mediaType: "image/png")
            ]
        )
        let content = provider.encodeMessage(msg)
        let data = try JSONEncoder().encode(content)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("inline_data"))
        #expect(json.contains("mime_type"))
        #expect(json.contains("image") && json.contains("png"))
    }

    @Test("Capabilities include thinking")
    func capabilitiesIncludeThinking() {
        let provider = GeminiProvider(overrideAPIKey: "x")
        #expect(provider.supportedCapabilities.contains(.thinking))
        #expect(provider.supportedCapabilities.contains(.vision))
        #expect(provider.supportedCapabilities.contains(.toolCalling))
    }
}
