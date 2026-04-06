import Foundation

public struct BooksTagsListTool: AITool {
    public static let name = "books_tags_list"
    public static let description = "List books with their associated tags. Optionally filtered by book IDs."
    public static let category = ToolCategory.bookLibrary
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let books = try await db.fetchBooks(query: nil, groupId: nil, limit: 100)
        return ToolResult(content: jsonString(["books": books]))
    }
}
