import Foundation

/// Internal tool used by the AI to decide whether a tool call needs user approval.
/// The AI checks risk level and returns an approval decision.
public struct ToolApprovalDeciderTool: AITool {
    public static let name = "tool_approval_decider"
    public static let description = "Internal: decide if a pending tool call requires user approval based on risk level and tool category."
    public static let category = ToolCategory.utility
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        let toolName = arguments["tool_name"] as? String ?? ""
        let riskLevel = arguments["risk_level"] as? String ?? "safe"
        let needsApproval = riskLevel == "dangerous" || riskLevel == "moderate"
        return ToolResult(content: jsonString([
            "tool_name": toolName,
            "needs_approval": needsApproval,
            "risk_level": riskLevel,
        ]))
    }
}
