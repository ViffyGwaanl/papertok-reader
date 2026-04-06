import Foundation

public struct CurrentChapterContentTool: AITool {
    public static let name = "current_chapter_content"
    public static let description = "Get the plain-text content of the current chapter being read."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe
    public var contentBridgeProvider: (@Sendable () async -> (any BookContentBridgeProtocol)?)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let provider = contentBridgeProvider, let bridge = await provider() else {
            return ToolResult(content: "No active book reader session", isError: true)
        }
        let href = arguments["href"] as? String ?? ""
        let text = try await bridge.chapterContent(href: href)
        return ToolResult(content: String(text.prefix(20_000)))
    }
}
