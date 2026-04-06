import Foundation

public struct SemanticSearchCurrentBookTool: AITool {
    public static let name = "semantic_search_current_book"
    public static let description = "Vector embedding search within the currently reading book. Requires pre-built index."
    public static let category = ToolCategory.search
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        ToolResult(content: jsonString(["status": "not_implemented", "note": "Semantic search index not yet built. Use book_content_search for keyword search."]))
    }
}
