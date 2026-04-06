import Foundation

public struct BookContentSearchTool: AITool {
    public static let name = "book_content_search"
    public static let description = "Full-text search within a specific book. Returns matching snippets with chapter context."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe
    public var contentBridgeProvider: (@Sendable () async -> (any BookContentBridgeProtocol)?)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return ToolResult(content: "Missing 'query' argument", isError: true)
        }
        guard let provider = contentBridgeProvider, let bridge = await provider() else {
            return ToolResult(content: "No active book reader session", isError: true)
        }
        let results = try await bridge.search(query: query)
        return ToolResult(content: results)
    }
}
