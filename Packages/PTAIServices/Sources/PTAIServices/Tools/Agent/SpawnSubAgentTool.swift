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
        let agentType = Self.normalizedAgentType(from: arguments)
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

    private static let validAgentTypes: Set<String> = ["research", "summarize", "verify"]

    private static func normalizedAgentType(from arguments: [String: Any]) -> String {
        for key in ["type", "agentType", "agent_type"] {
            guard let rawValue = arguments[key] as? String else { continue }
            let normalized = rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if validAgentTypes.contains(normalized) {
                return normalized
            }
        }
        return "research"
    }
}
