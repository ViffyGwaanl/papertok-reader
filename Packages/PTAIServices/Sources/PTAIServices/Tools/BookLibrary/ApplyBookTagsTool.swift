import Foundation

public struct ApplyBookTagsTool: AITool {
    public static let name = "apply_book_tags"
    public static let description = "Apply or remove tags from books. Requires user confirmation (riskLevel: moderate)."
    public static let category = ToolCategory.bookLibrary
    public static let riskLevel = ToolRiskLevel.moderate

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        // Actual tag writes handled after approval in App Target.
        // Tool returns the intended changes for display in ToolApprovalSheet.
        let changes = arguments["changes"] as? [[String: Any]] ?? []
        return ToolResult(content: jsonString(["pendingChanges": changes, "status": "awaiting_approval"]))
    }
}
