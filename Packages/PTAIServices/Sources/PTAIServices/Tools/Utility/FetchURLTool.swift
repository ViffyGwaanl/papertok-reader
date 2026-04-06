import Foundation

public struct FetchURLTool: AITool {
    public static let name = "fetch_url"
    public static let description = "Fetch text content from an HTTP/HTTPS URL. Returns plain text (HTML stripped). Max 50KB."
    public static let category = ToolCategory.utility
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let urlString = arguments["url"] as? String,
              let url = URL(string: urlString),
              url.scheme == "https" || url.scheme == "http" else {
            return ToolResult(content: "Invalid or missing 'url' argument", isError: true)
        }
        if let host = url.host, isPrivateHost(host) {
            return ToolResult(content: "Access to private/local addresses is not allowed", isError: true)
        }
        guard let client = context.httpClient else {
            return ToolResult(content: "HTTP client not available in this context", isError: true)
        }
        let timeout = arguments["timeout_seconds"] as? Double ?? 15.0
        let text = try await client.fetchText(url: url, timeoutSeconds: timeout)
        let truncated = String(text.prefix(50_000))
        return ToolResult(content: truncated)
    }

    private func isPrivateHost(_ host: String) -> Bool {
        ["localhost", "127.", "10.", "192.168.", "172.16.", "::1"].contains { host.hasPrefix($0) }
    }
}
