import Foundation

public struct BookshelfLookupTool: AITool {
    public static let name = "bookshelf_lookup"
    public static let description = "Find books on the user's local shelf by title, author, or group. Returns structured list with metadata and reading progress."
    public static let category = ToolCategory.bookLibrary
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let query = arguments["query"] as? String
        let groupId = arguments["group_id"] as? Int64
        let limit = arguments["limit"] as? Int ?? 20
        let books = try await db.fetchBooks(query: query, groupId: groupId, limit: limit)
        return ToolResult(content: jsonString(["results": books, "count": books.count]))
    }
}
