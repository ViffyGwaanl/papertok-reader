import Foundation

public struct MemorySearchTool: AITool {
    public static let name = "memory_search"
    public static let description = "Search memory files by keyword or date range."
    public static let category = ToolCategory.memory
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let dir = context.memoryDirectory else {
            return ToolResult(content: "Memory directory not configured", isError: true)
        }
        let keyword = (arguments["keyword"] as? String ?? "").lowercased()
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
        var matches: [[String: String]] = []
        for file in files {
            let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            if keyword.isEmpty || content.lowercased().contains(keyword) {
                matches.append(["filename": file.lastPathComponent, "snippet": String(content.prefix(200))])
            }
        }
        return ToolResult(content: jsonString(["matches": matches, "count": "\(matches.count)"]))
    }
}
