import Foundation

public struct CurrentReadingMetadataTool: AITool {
    public static let name = "current_reading_metadata"
    public static let description = "Get metadata for the currently active reading session: book ID, title, progress percentage, and current chapter."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let bookId = context.bookId else {
            return ToolResult(content: jsonString(["status": "no_active_book"]))
        }
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let books = try await db.fetchBooks(query: nil, groupId: nil, limit: 200)
        if let book = books.first(where: { ($0["id"] as? Int64) == bookId }) {
            return ToolResult(content: jsonString(["book": book]))
        }
        return ToolResult(content: "Book not found", isError: true)
    }
}
