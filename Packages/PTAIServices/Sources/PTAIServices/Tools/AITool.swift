import Foundation

public protocol AITool: Sendable {
    static var name: String { get }
    static var description: String { get }
    static var category: ToolCategory { get }
    static var riskLevel: ToolRiskLevel { get }
    func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult
}

public enum ToolCategory: String, Sendable, CaseIterable {
    case bookLibrary, bookContent, annotation, search, readingHistory, calendar, reminders, utility, agent, memory, mindmap
}

public enum ToolRiskLevel: String, Sendable { case safe, moderate, dangerous }

public struct ToolResult: Sendable {
    public let toolCallId: String
    public let content: String
    public let isError: Bool
    public init(toolCallId: String = "", content: String, isError: Bool = false) {
        self.toolCallId = toolCallId; self.content = content; self.isError = isError
    }
}
