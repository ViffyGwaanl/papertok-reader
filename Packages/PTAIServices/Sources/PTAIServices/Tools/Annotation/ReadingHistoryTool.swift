import Foundation

public struct ReadingHistoryTool: AITool {
    public static let name = "reading_history"
    public static let description = "Query historical reading sessions with optional date range and book ID filters."
    public static let category = ToolCategory.readingHistory
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let bookId = arguments["book_id"] as? Int64
        let sessions = try await db.fetchReadingTime(bookId: bookId, since: nil)
        return ToolResult(content: jsonString(["sessions": sessions, "count": sessions.count]))
    }
}
