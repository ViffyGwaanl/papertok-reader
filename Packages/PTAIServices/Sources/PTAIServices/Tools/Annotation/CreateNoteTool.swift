import Foundation

public struct CreateNoteTool: AITool {
    public static let name = "create_note"
    public static let description = "Create a text note (bookmark-type annotation) at a book position."
    public static let category = ToolCategory.annotation
    public static let riskLevel = ToolRiskLevel.moderate

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let cfi = arguments["cfi"] as? String,
              let content = arguments["content"] as? String else {
            return ToolResult(content: "Missing 'cfi' or 'content' argument", isError: true)
        }
        guard let bookId = context.activeBookId, let db = context.database else {
            return ToolResult(content: "No active session or database", isError: true)
        }
        let chapter = arguments["chapter"] as? String ?? ""
        let readerNote = arguments["reader_note"] as? String ?? ""
        let fields: [String: Any] = [
            "book_id": bookId, "content": content, "cfi": cfi,
            "color": "", "type": "note", "chapter": chapter,
            "reader_note": readerNote,
        ]
        try await db.insertBookNote(fields)
        return ToolResult(content: jsonString(["status": "created", "cfi": cfi]))
    }
}
