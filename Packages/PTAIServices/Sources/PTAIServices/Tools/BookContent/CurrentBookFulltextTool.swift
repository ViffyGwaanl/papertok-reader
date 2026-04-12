import Foundation

public struct CurrentBookFulltextTool: AITool {
    public static let name = "current_book_fulltext"
    public static let description = "Retrieve full text of the current book. Only use for short books (< 50K chars). Returns error for long books."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let session = await context.activeReaderSession() else {
            return ToolResult(content: "No active book reader session", isError: true)
        }
        let text = try await session.bridge.fullText()
        if text.count >= 50_000 {
            return ToolResult(content: "Book too long for full-text retrieval. Use book_content_search to search specific passages instead.", isError: true)
        }
        return ToolResult(content: text)
    }
}
