import Foundation

public actor ToolOrchestrator {
    private var tools: [String: any AITool] = [:]
    public init() {}

    public func register(_ tool: any AITool) { tools[type(of: tool).name] = tool }

    public func execute(calls: [ToolCall], context: ToolContext) async throws -> [ToolResult] {
        // Capture tools snapshot before entering task group to avoid actor reentrancy issues
        let toolsSnapshot = tools
        return try await withThrowingTaskGroup(of: (Int, ToolResult).self) { group in
            for (index, call) in calls.enumerated() {
                group.addTask { (index, await Self.executeSingle(call: call, context: context, tools: toolsSnapshot)) }
            }
            var results = Array(repeating: ToolResult(content: ""), count: calls.count)
            for try await (index, result) in group { results[index] = result }
            return results
        }
    }

    private static func executeSingle(call: ToolCall, context: ToolContext, tools: [String: any AITool]) async -> ToolResult {
        guard let tool = tools[call.name] else {
            return ToolResult(toolCallId: call.id, content: "Error: Unknown tool '\(call.name)'", isError: true)
        }
        do {
            let args = parseArguments(call.arguments)
            let result = try await tool.execute(arguments: args, context: context)
            return ToolResult(toolCallId: call.id, content: result.content, isError: result.isError)
        } catch {
            return ToolResult(toolCallId: call.id, content: "Error: \(error.localizedDescription)", isError: true)
        }
    }

    private static func parseArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return dict
    }
}
