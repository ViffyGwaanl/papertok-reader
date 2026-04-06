import Foundation

public struct MindmapTool: AITool {
    public static let name = "mindmap_draw"
    public static let description = "Transform a hierarchical bullet list into a mind map JSON structure for rendering."
    public static let category = ToolCategory.utility
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let content = arguments["content"] as? String, !content.isEmpty else {
            return ToolResult(content: "Missing 'content' argument", isError: true)
        }
        let root = parseBulletList(content)
        guard let json = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]),
              let jsonStr = String(data: json, encoding: .utf8) else {
            return ToolResult(content: "Failed to serialize mindmap", isError: true)
        }
        return ToolResult(content: jsonStr)
    }

    private func parseBulletList(_ text: String) -> [String: Any] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let first = lines.first else { return [:] }
        return ["text": first.trimmingCharacters(in: .init(charactersIn: "- ")), "children": [] as [[String: Any]]]
    }
}
