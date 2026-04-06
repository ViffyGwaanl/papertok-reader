import Foundation

public struct CurrentTimeTool: AITool {
    public static let name = "current_time"
    public static let description = "Get the current device time in ISO-8601 format, Unix timestamp, and timezone name."
    public static let category = ToolCategory.utility
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now)
        let timestamp = Int(now.timeIntervalSince1970)
        let tz = TimeZone.current.identifier
        let result: [String: Any] = ["iso8601": iso, "timestamp": timestamp, "timezone": tz]
        return ToolResult(content: jsonString(result))
    }
}
