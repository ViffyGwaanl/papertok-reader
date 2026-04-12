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
        let keyword = (arguments["keyword"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = (arguments["limit"] as? Int) ?? 20

        // Prefer FTS5 index when available and we have a non-empty keyword.
        if let index = context.memoryIndex, !keyword.isEmpty {
            do {
                _ = try await index.indexAllFiles(in: dir)
                let hits = try await index.search(query: keyword, limit: limit)
                let matches: [[String: String]] = hits.map { hit in
                    [
                        "filename": (hit.path as NSString).lastPathComponent,
                        "path": hit.path,
                        "snippet": hit.snippet,
                        "date": hit.date,
                    ]
                }
                return ToolResult(content: jsonString([
                    "matches": matches,
                    "count": "\(matches.count)",
                    "source": "fts5",
                ]))
            } catch {
                // Fall through to linear scan on index failure.
            }
        }

        // Linear fallback (original behavior).
        let lowered = keyword.lowercased()
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
        var matches: [[String: String]] = []
        for file in files {
            let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            if lowered.isEmpty || content.lowercased().contains(lowered) {
                matches.append(["filename": file.lastPathComponent, "snippet": String(content.prefix(200))])
            }
            if matches.count >= limit { break }
        }
        return ToolResult(content: jsonString([
            "matches": matches,
            "count": "\(matches.count)",
            "source": "scan",
        ]))
    }
}
