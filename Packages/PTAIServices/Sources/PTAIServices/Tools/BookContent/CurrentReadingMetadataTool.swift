import Foundation

public struct CurrentReadingMetadataTool: AITool {
    public static let name = "current_reading_metadata"
    public static let description = "Get metadata for the currently active reading session: book ID, title, progress percentage, and current chapter."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        let snapshot = context.readerSessionSnapshot()
        guard let bookId = snapshot?.bookId ?? context.bookId else {
            return ToolResult(content: jsonString(["status": "no_active_book"]))
        }
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        guard let book = try await db.fetchBook(id: bookId) else {
            return ToolResult(content: "Book not found", isError: true)
        }
        var payload: [String: Any] = ["book": book]
        if let progress = snapshot?.readingProgress {
            payload["progress"] = progress
        }
        if let chapterTitle = snapshot?.chapterTitle, chapterTitle.isEmpty == false {
            payload["chapter_title"] = chapterTitle
        }
        return ToolResult(content: jsonString(payload))
    }
}
