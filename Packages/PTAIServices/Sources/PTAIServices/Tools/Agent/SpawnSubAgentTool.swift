import Foundation

public struct SpawnSubAgentTool: AITool {
    public static let name = "spawn_sub_agent"
    public static let description = "Spawn a focused sub-agent (research/summarize/verify) with a restricted tool set and limited steps (1-15)."
    public static let category = ToolCategory.agent
    public static let riskLevel = ToolRiskLevel.moderate

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let task = arguments["task"] as? String, task.isEmpty == false else {
            return ToolResult(content: "Missing 'task' argument", isError: true)
        }
        let agentType = arguments["type"] as? String ?? "research"
        let requestedSteps = (arguments["steps"] as? Int).map { min(max($0, 1), 15) }

        guard let service = context.subAgentService else {
            return ToolResult(
                content: jsonString([
                    "status": "unsupported",
                    "error_type": "missing_runtime_prerequisite",
                    "requires": "subAgentService",
                    "task": task,
                    "agent_type": agentType,
                ]),
                isError: true
            )
        }

        let result = try await service.spawn(task: task, type: agentType, requestedSteps: requestedSteps)
        return ToolResult(content: jsonString(result.jsonValue))
    }
}
