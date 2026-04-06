import Foundation

/// Central registry of all 46 AI tools.
///
/// Usage:
/// ```swift
/// let registry = ToolRegistry()
/// let tool = registry.tool(named: "calculator")
/// let definitions = registry.allDefinitions()
/// ```
public final class ToolRegistry: @unchecked Sendable {
    public static let `default` = ToolRegistry()

    private let tools: [String: any AITool]

    public init(extras: [any AITool] = []) {
        var map: [String: any AITool] = [:]
        let builtIns: [any AITool] = [
            // Utility (6)
            CurrentTimeTool(),
            CalculatorTool(),
            FetchURLTool(),
            WebSearchTool(),
            MindmapTool(),
            ToolApprovalDeciderTool(),
            // BookLibrary (5)
            BookshelfLookupTool(),
            BookshelfOrganizeTool(),
            BooksTagsListTool(),
            TagsListTool(),
            ApplyBookTagsTool(),
            // BookContent (7)
            CurrentReadingMetadataTool(),
            CurrentBookTOCTool(),
            CurrentChapterContentTool(),
            CurrentBookFulltextTool(),
            ChapterContentByHrefTool(),
            ResolveCFITool(),
            BookContentSearchTool(),
            // Annotation (3)
            CreateHighlightTool(),
            CreateNoteTool(),
            NotesSearchTool(),
            // ReadingHistory (1)
            ReadingHistoryTool(),
            // Search (2)
            SemanticSearchCurrentBookTool(),
            SemanticSearchLibraryTool(),
            // Calendar (6)
            CalendarListCalendarsTool(),
            CalendarListEventsTool(),
            CalendarGetEventTool(),
            CalendarCreateEventTool(),
            CalendarUpdateEventTool(),
            CalendarDeleteEventTool(),
            // Reminders (11)
            RemindersListListsTool(),
            RemindersListTool(),
            RemindersGetTool(),
            RemindersCreateTool(),
            RemindersUpdateTool(),
            RemindersDeleteTool(),
            RemindersCompleteTool(),
            RemindersUncompleteTool(),
            RemindersListCreateTool(),
            RemindersListDeleteTool(),
            RemindersListRenameTool(),
            // Memory (3)
            MemoryReadTool(),
            MemoryWriteTool(),
            MemorySearchTool(),
            // Agent (2)
            SpawnSubAgentTool(),
            ShortcutsRunTool(),
        ]
        for tool in builtIns + extras {
            map[type(of: tool).name] = tool
        }
        self.tools = map
    }

    /// Look up a tool by its registered name.
    public func tool(named name: String) -> (any AITool)? { tools[name] }

    /// All registered tools.
    public var allTools: [any AITool] { Array(tools.values) }

    /// Total number of registered tools.
    public var count: Int { tools.count }

    /// Generate `ToolDefinition` array suitable for passing to LLM API calls.
    public func allDefinitions() -> [ToolDefinition] {
        allTools.map { tool in
            ToolDefinition(
                name: type(of: tool).name,
                description: type(of: tool).description
            )
        }
    }

    /// Register all tools into a ToolOrchestrator for concurrent execution.
    public func registerAll(into orchestrator: ToolOrchestrator) async {
        for tool in allTools {
            await orchestrator.register(tool)
        }
    }
}
