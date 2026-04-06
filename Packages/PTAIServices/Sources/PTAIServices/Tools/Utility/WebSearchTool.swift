import Foundation

public struct WebSearchTool: AITool {
    public static let name = "web_search"
    public static let description = "Search the web using Serper API. Returns top results with title, URL, snippet."
    public static let category = ToolCategory.utility
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return ToolResult(content: "Missing 'query' argument", isError: true)
        }
        guard let client = context.httpClient else {
            return ToolResult(content: "HTTP client not available", isError: true)
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://google.serper.dev/search?q=\(encoded)") else {
            return ToolResult(content: "Failed to build search URL", isError: true)
        }
        let resultText = try await client.fetchText(url: url, timeoutSeconds: 10)
        return ToolResult(content: String(resultText.prefix(10_000)))
    }
}
