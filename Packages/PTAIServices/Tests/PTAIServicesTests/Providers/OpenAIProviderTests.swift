import Foundation
import Testing
@testable import PTAIServices

@Suite("OpenAIProvider")
struct OpenAIProviderTests {
    @Test("request body encodes advanced generation defaults")
    func requestBodyEncodesAdvancedGenerationDefaults() throws {
        let provider = OpenAIProvider(overrideAPIKey: "test-key")
        let request = ChatRequest(
            messages: [
                .system("You are precise."),
                .user("Hello")
            ],
            model: "gpt-4.1",
            temperature: 0.4,
            maxTokens: 512,
            topP: 0.77,
            presencePenalty: 0.2,
            frequencyPenalty: -0.1,
            stopSequences: ["END", "STOP"]
        )

        let body = provider.buildRequestBody(request: request, stream: false)
        #expect(body.temperature == 0.4)
        #expect(body.maxTokens == 512)
        #expect(body.topP == 0.77)
        #expect(body.presencePenalty == 0.2)
        #expect(body.frequencyPenalty == -0.1)
        #expect(body.stop == ["END", "STOP"])

        let data = try JSONEncoder().encode(body)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"top_p\":0.77"))
        #expect(json.contains("\"presence_penalty\":0.2"))
        #expect(json.contains("\"frequency_penalty\":-0.1"))
        #expect(json.contains("\"stop\":[\"END\",\"STOP\"]"))
    }

    @Test("request body encodes reasoning effort for thinking models")
    func requestBodyEncodesReasoningEffort() throws {
        let provider = OpenAIProvider(overrideAPIKey: "test-key")
        let request = ChatRequest(
            messages: [.user("Think carefully")],
            model: "gpt-5",
            thinkingLevel: .minimal
        )

        let body = provider.buildRequestBody(request: request, stream: false)
        #expect(body.reasoningEffort == "minimal")

        let data = try JSONEncoder().encode(body)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"reasoning_effort\":\"minimal\""))
    }

    @Test("capabilities include thinking")
    func capabilitiesIncludeThinking() {
        let provider = OpenAIProvider(overrideAPIKey: "test-key")
        #expect(provider.supportedCapabilities.contains(.thinking))
    }

    @Test("openAIProviderSendsIncludeUsageFlag")
    func openAIProviderSendsIncludeUsageFlag() throws {
        let provider = OpenAIProvider(overrideAPIKey: "test-key")
        let request = ChatRequest(messages: [.user("Hi")], model: "gpt-4o")

        let streamBody = provider.buildRequestBody(request: request, stream: true)
        #expect(streamBody.streamOptions?.includeUsage == true)

        let nonStreamBody = provider.buildRequestBody(request: request, stream: false)
        #expect(nonStreamBody.streamOptions == nil)

        let data = try JSONEncoder().encode(streamBody)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"stream_options\":{\"include_usage\":true}"))
    }

    @Test("response body sets json_object when JSON format selected")
    func responseFormatJSONEncodesJsonObject() throws {
        let provider = OpenAIProvider(overrideAPIKey: "test-key")
        let request = ChatRequest(
            messages: [.user("Return JSON")],
            model: "gpt-4o",
            responseFormat: .json
        )

        let body = provider.buildRequestBody(request: request, stream: false)
        #expect(body.responseFormat?.type == "json_object")

        let data = try JSONEncoder().encode(body)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"response_format\":{\"type\":\"json_object\"}"))
    }

    @Test("response body omits response_format for text (default) mode")
    func responseFormatTextOmitted() throws {
        let provider = OpenAIProvider(overrideAPIKey: "test-key")
        let textRequest = ChatRequest(
            messages: [.user("Say hi")],
            model: "gpt-4o",
            responseFormat: .text
        )
        let body = provider.buildRequestBody(request: textRequest, stream: false)
        #expect(body.responseFormat == nil)

        let nilRequest = ChatRequest(messages: [.user("Say hi")], model: "gpt-4o")
        let nilBody = provider.buildRequestBody(request: nilRequest, stream: false)
        #expect(nilBody.responseFormat == nil)

        let data = try JSONEncoder().encode(body)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("response_format") == false)
    }

    @Test("request body includes penalties when non-zero")
    func openAIRequestIncludesPenaltiesWhenNonZero() throws {
        let provider = OpenAIProvider(overrideAPIKey: "test-key")
        let request = ChatRequest(
            messages: [.user("Hi")],
            model: "gpt-4o",
            presencePenalty: 0.7,
            frequencyPenalty: -0.5
        )
        let body = provider.buildRequestBody(request: request, stream: false)
        #expect(body.presencePenalty == 0.7)
        #expect(body.frequencyPenalty == -0.5)
        let data = try JSONEncoder().encode(body)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"presence_penalty\":0.7"))
        #expect(json.contains("\"frequency_penalty\":-0.5"))
    }

    @Test("request body includes stop sequences as `stop` field")
    func openAIRequestIncludesStopSequences() throws {
        let provider = OpenAIProvider(overrideAPIKey: "test-key")
        let request = ChatRequest(
            messages: [.user("Hi")],
            model: "gpt-4o",
            stopSequences: ["END", "DONE"]
        )
        let body = provider.buildRequestBody(request: request, stream: false)
        #expect(body.stop == ["END", "DONE"])
        let data = try JSONEncoder().encode(body)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"stop\":[\"END\",\"DONE\"]"))
    }

    @Test("OpenAI request ignores thinking budget tokens")
    func openAIRequestIgnoresThinkingBudget() throws {
        let provider = OpenAIProvider(overrideAPIKey: "test-key")
        let request = ChatRequest(
            messages: [.user("Hi")],
            model: "gpt-5",
            thinkingBudgetTokens: 16_384
        )
        let body = provider.buildRequestBody(request: request, stream: false)
        let data = try JSONEncoder().encode(body)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("budget_tokens") == false)
        #expect(json.contains("thinking_budget") == false)
    }

    @Test("openAIProviderDecodesUsageOnFinalChunk")
    func openAIProviderDecodesUsageOnFinalChunk() throws {
        // Final OpenAI streaming chunk: empty choices array, usage populated.
        let json = """
        {"choices":[],"usage":{"prompt_tokens":42,"completion_tokens":17,"total_tokens":59}}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OAIStreamResponse.self, from: json)

        #expect(response.choices.isEmpty)
        #expect(response.usage?.promptTokens == 42)
        #expect(response.usage?.completionTokens == 17)
        #expect(response.usage?.totalTokens == 59)
    }
}
