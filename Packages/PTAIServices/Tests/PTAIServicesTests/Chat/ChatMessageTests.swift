import Testing
import Foundation
@testable import PTAIServices

@Suite("ChatMessage")
struct ChatMessageTests {
    @Test("Creates user message")
    func userMessage() {
        let msg = ChatMessage.user("Hello")
        #expect(msg.role == .user)
        #expect(msg.textContent == "Hello")
    }

    @Test("Creates assistant message")
    func assistantMessage() {
        let msg = ChatMessage.assistant("Hi there")
        #expect(msg.role == .assistant)
        #expect(msg.textContent == "Hi there")
    }

    @Test("Creates system message")
    func systemMessage() {
        let msg = ChatMessage.system("You are helpful")
        #expect(msg.role == .system)
    }

    @Test("Creates tool result message")
    func toolResultMessage() {
        let msg = ChatMessage.toolResult(toolCallId: "call_1", content: "42")
        #expect(msg.role == .tool)
        #expect(msg.toolCallId == "call_1")
    }

    @Test("TokenUsage calculates total")
    func tokenUsageTotal() {
        let usage = TokenUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150)
        #expect(usage.totalTokens == 150)
    }

    @Test("TokenUsage estimates cost")
    func tokenUsageCost() {
        let usage = TokenUsage(promptTokens: 1000, completionTokens: 500, totalTokens: 1500)
        let cost = usage.estimateCost(inputPricePer1M: 3.0, outputPricePer1M: 15.0)
        #expect(abs(cost - 0.0105) < 0.001)
    }
}
