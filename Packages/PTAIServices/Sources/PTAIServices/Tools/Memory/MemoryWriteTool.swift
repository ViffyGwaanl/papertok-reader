import Foundation

public struct MemoryWriteTool: AITool {
    public static let name = "memory_write"
    public static let description = "Write or append to markdown memory files (MEMORY.md or daily notes). Risk: modifies persistent memory."
    public static let category = ToolCategory.memory
    public static let riskLevel = ToolRiskLevel.moderate

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let dir = context.memoryDirectory else {
            return ToolResult(content: "Memory directory not configured", isError: true)
        }
        guard let content = arguments["content"] as? String else {
            return ToolResult(content: "Missing 'content' argument", isError: true)
        }
        let filename = arguments["filename"] as? String ?? "MEMORY.md"
        let append = arguments["append"] as? Bool ?? true
        let fileURL = dir.appendingPathComponent(filename)
        if append, FileManager.default.fileExists(atPath: fileURL.path) {
            let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            try (existing + "\n" + content).write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return ToolResult(content: jsonString(["filename": filename, "status": "written"]))
    }
}
