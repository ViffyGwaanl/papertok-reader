import Foundation

public struct ChapterContentByHrefTool: AITool {
    public static let name = "chapter_content_by_href"
    public static let description = "Retrieve chapter content by TOC href identifier."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe
    public var contentBridgeProvider: (@Sendable () async -> (any BookContentBridgeProtocol)?)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let href = arguments["href"] as? String, !href.isEmpty else {
            return ToolResult(content: "Missing 'href' argument", isError: true)
        }
        guard let provider = contentBridgeProvider, let bridge = await provider() else {
            return ToolResult(content: "No active book reader session", isError: true)
        }
        let text = try await bridge.chapterContent(href: href)
        return ToolResult(content: String(text.prefix(20_000)))
    }
}
