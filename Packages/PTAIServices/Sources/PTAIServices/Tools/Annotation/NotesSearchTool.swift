import Foundation

public struct NotesSearchTool: AITool {
    public static let name = "notes_search"
    public static let description = "Search notes by keyword, book ID, or date range. Returns matching annotations."
    public static let category = ToolCategory.annotation
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let keyword = arguments["keyword"] as? String
        let bookId = arguments["book_id"] as? Int64
        let limit = arguments["limit"] as? Int ?? 20
        let notes = try await db.fetchBookNotes(bookId: bookId, keyword: keyword, limit: limit)
        return ToolResult(content: jsonString(["notes": notes, "count": notes.count]))
    }
}
