import Testing
@testable import PTAIServices

@Suite("SpawnSubAgentTool")
struct SpawnSubAgentToolTests {
    actor MockSubAgentService: SubAgentServiceProtocol {
        private(set) var capturedTask: String?
        private(set) var capturedType: String?
        private(set) var capturedRequestedSteps: Int?

        func spawn(task: String, type: String, requestedSteps: Int?) async throws -> SubAgentSpawnResult {
            capturedTask = task
            capturedType = type
            capturedRequestedSteps = requestedSteps
            return SubAgentSpawnResult(status: "ok", summary: "stub", agentType: type, requestedSteps: requestedSteps)
        }
    }

    @Test("accepts agentType alias when type is omitted")
    func agentTypeAlias() async throws {
        let service = MockSubAgentService()
        let tool = SpawnSubAgentTool()

        _ = try await tool.execute(
            arguments: ["task": "t", "agentType": "summarize", "steps": 3],
            context: ToolContext(subAgentService: service)
        )

        let capturedType = await service.capturedType
        #expect(capturedType == "summarize")
    }

    @Test("type takes precedence over agentType when both are provided")
    func typePrecedence() async throws {
        let service = MockSubAgentService()
        let tool = SpawnSubAgentTool()

        _ = try await tool.execute(
            arguments: ["task": "t", "type": "verify", "agentType": "summarize"],
            context: ToolContext(subAgentService: service)
        )

        let capturedType = await service.capturedType
        #expect(capturedType == "verify")
    }

    @Test("falls back to the first valid alias when type is blank")
    func blankTypeFallsBackToAlias() async throws {
        let service = MockSubAgentService()
        let tool = SpawnSubAgentTool()

        _ = try await tool.execute(
            arguments: ["task": "t", "type": "   ", "agentType": "summarize"],
            context: ToolContext(subAgentService: service)
        )

        let capturedType = await service.capturedType
        #expect(capturedType == "summarize")
    }

    @Test("falls back to research when all provided types are invalid")
    func invalidTypeFallsBackToDefault() async throws {
        let service = MockSubAgentService()
        let tool = SpawnSubAgentTool()

        _ = try await tool.execute(
            arguments: ["task": "t", "type": "builder", "agentType": "writer"],
            context: ToolContext(subAgentService: service)
        )

        let capturedType = await service.capturedType
        #expect(capturedType == "research")
    }
}
