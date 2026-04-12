import Foundation

public struct CurrentChapterContentTool: AITool {
    public static let name = "current_chapter_content"
    public static let description = "Get the plain-text content of the current chapter being read."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let session = await context.activeReaderSession() else {
            return ToolResult(content: "No active book reader session", isError: true)
        }
        guard let href = (arguments["href"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? session.snapshot.locationHref else {
            return ToolResult(content: "No active chapter in the current reader session", isError: true)
        }
        let text = try await session.bridge.chapterContent(href: href)
        return ToolResult(content: text)
    }
}
