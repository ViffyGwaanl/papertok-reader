import Testing
import Foundation
@testable import PTAIServices

struct MockCalculatorTool: AITool {
    static let name = "calculator"
    static let description = "Evaluates math"
    static let category = ToolCategory.utility
    static let riskLevel = ToolRiskLevel.safe
    func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        ToolResult(content: "Result: 42")
    }
}

struct MockSlowTool: AITool {
    static let name = "slow_tool"
    static let description = "A slow tool"
    static let category = ToolCategory.utility
    static let riskLevel = ToolRiskLevel.safe
    func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        try await Task.sleep(for: .milliseconds(50))
        return ToolResult(content: "slow done")
    }
}

@Suite("ToolOrchestrator")
struct ToolOrchestratorTests {
    @Test("Executes a single tool call")
    func singleExecution() async throws {
        let orchestrator = ToolOrchestrator()
        await orchestrator.register(MockCalculatorTool())
        let call = ToolCall(id: "call_1", name: "calculator", arguments: "{}")
        let results = try await orchestrator.execute(calls: [call], context: ToolContext())
        #expect(results.count == 1)
        #expect(results[0].content.contains("42"))
    }

    @Test("Executes multiple safe tools concurrently")
    func concurrentExecution() async throws {
        let orchestrator = ToolOrchestrator()
        await orchestrator.register(MockSlowTool())
        let calls = (0..<3).map { ToolCall(id: "call_\($0)", name: "slow_tool", arguments: "{}") }
        let start = Date()
        let results = try await orchestrator.execute(calls: calls, context: ToolContext())
        let elapsed = Date().timeIntervalSince(start)
        #expect(results.count == 3)
        #expect(elapsed < 0.15)
    }

    @Test("Returns error for unknown tool")
    func unknownTool() async throws {
        let orchestrator = ToolOrchestrator()
        let call = ToolCall(id: "call_1", name: "nonexistent", arguments: "{}")
        let results = try await orchestrator.execute(calls: [call], context: ToolContext())
        #expect(results[0].isError)
    }
}
