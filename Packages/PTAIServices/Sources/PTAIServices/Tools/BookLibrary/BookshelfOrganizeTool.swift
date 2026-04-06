import Foundation

public struct BookshelfOrganizeTool: AITool {
    public static let name = "bookshelf_organize"
    public static let description = "Draft a bookshelf reorganization plan: moving books to groups, renaming groups. Returns a plan JSON; user must confirm before execution."
    public static let category = ToolCategory.bookLibrary
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        let moves = arguments["moves"] as? [[String: Any]] ?? []
        let renames = arguments["renames"] as? [[String: Any]] ?? []
        return ToolResult(content: jsonString(["plan": ["moves": moves, "renames": renames], "requiresConfirmation": true]))
    }
}
