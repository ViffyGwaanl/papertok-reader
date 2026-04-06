import Foundation

public struct MemoryReadTool: AITool {
    public static let name = "memory_read"
    public static let description = "Read markdown memory files: MEMORY.md (long-term) or YYYY-MM-DD.md (daily notes)."
    public static let category = ToolCategory.memory
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let dir = context.memoryDirectory else {
            return ToolResult(content: "Memory directory not configured", isError: true)
        }
        let filename = arguments["filename"] as? String ?? "MEMORY.md"
        let fileURL = dir.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ToolResult(content: jsonString(["filename": filename, "content": "", "exists": false]))
        }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return ToolResult(content: jsonString(["filename": filename, "content": content, "exists": true]))
    }
}
