import Foundation

public struct TagsListTool: AITool {
    public static let name = "tags_list"
    public static let description = "List all book tags with their ID, name, and color."
    public static let category = ToolCategory.bookLibrary
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let tags = try await db.fetchTags()
        return ToolResult(content: jsonString(["tags": tags]))
    }
}
