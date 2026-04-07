import Foundation

public struct ShortcutsRunTool: AITool {
    public static let name = "shortcuts_run"
    public static let description = "Run an iOS Shortcut by name via x-callback-url. Dangerous: executes arbitrary user shortcuts."
    public static let category = ToolCategory.agent
    public static let riskLevel = ToolRiskLevel.dangerous

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let shortcutName = arguments["shortcut_name"] as? String else {
            return ToolResult(content: "Missing 'shortcut_name' argument", isError: true)
        }
        let input = arguments["input"] as? String

        guard let service = context.shortcutsService else {
            return ToolResult(
                content: jsonString([
                    "status": "unsupported",
                    "error_type": "missing_runtime_prerequisite",
                    "requires": "shortcutsService",
                    "shortcut_name": shortcutName,
                ]),
                isError: true
            )
        }

        let result = try await service.runShortcut(named: shortcutName, input: input)
        return ToolResult(content: jsonString(result.jsonValue))
    }
}
