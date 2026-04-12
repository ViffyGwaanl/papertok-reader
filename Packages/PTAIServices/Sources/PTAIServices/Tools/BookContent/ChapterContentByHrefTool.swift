import Foundation

public struct ChapterContentByHrefTool: AITool {
    public static let name = "chapter_content_by_href"
    public static let description = "Retrieve chapter content by TOC href identifier."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let href = arguments["href"] as? String, !href.isEmpty else {
            return ToolResult(content: "Missing 'href' argument", isError: true)
        }
        guard let session = await context.activeReaderSession() else {
            return ToolResult(content: "No active book reader session", isError: true)
        }
        let text = try await session.bridge.chapterContent(href: href)
        return ToolResult(content: text)
    }
}
