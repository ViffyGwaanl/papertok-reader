import Foundation

public struct CurrentBookTOCTool: AITool {
    public static let name = "current_book_toc"
    public static let description = "Retrieve the table of contents for the currently reading book."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe
    public var contentBridgeProvider: (@Sendable () async -> (any BookContentBridgeProtocol)?)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let provider = contentBridgeProvider, let bridge = await provider() else {
            return ToolResult(content: "No active book reader session", isError: true)
        }
        let toc = try await bridge.tableOfContentsJSON()
        return ToolResult(content: toc)
    }
}
