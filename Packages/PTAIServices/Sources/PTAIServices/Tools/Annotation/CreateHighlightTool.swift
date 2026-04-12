import Foundation

public struct CreateHighlightTool: AITool {
    public static let name = "create_highlight"
    public static let description = "Create a highlight annotation at a book position. Color options: yellow, green, blue, red, purple. Risk: writes to database."
    public static let category = ToolCategory.annotation
    public static let riskLevel = ToolRiskLevel.moderate

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let cfi = arguments["cfi"] as? String,
              let content = arguments["content"] as? String else {
            return ToolResult(content: "Missing 'cfi' or 'content' argument", isError: true)
        }
        guard let bookId = context.activeBookId else {
            return ToolResult(content: "No active book session", isError: true)
        }
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let colorMap: [String: String] = [
            "yellow": "#FFEB3B", "green": "#A5D6A7",
            "blue": "#90CAF9", "red": "#EF9A9A", "purple": "#CE93D8",
        ]
        let colorName = arguments["color"] as? String ?? "yellow"
        let color = colorMap[colorName] ?? "#FFEB3B"
        let chapter = arguments["chapter"] as? String ?? ""
        let fields: [String: Any] = [
            "book_id": bookId, "content": content, "cfi": cfi,
            "color": color, "type": "highlight", "chapter": chapter,
        ]
        try await db.insertBookNote(fields)
        return ToolResult(content: jsonString(["status": "created", "cfi": cfi, "color": color]))
    }
}
