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
                description: type(of: tool).description,
                parameters: Self.schema(forToolNamed: type(of: tool).name)
            )
        }
    }

    /// Register all tools into a ToolOrchestrator for concurrent execution.
    public func registerAll(into orchestrator: ToolOrchestrator) async {
        for tool in allTools {
            await orchestrator.register(tool)
        }
    }

    private static func schema(forToolNamed name: String) -> ToolParametersSchema? {
        switch name {
        case "calculator":
            return ToolParametersSchema(
                properties: [
                    "expression": ToolPropertySchema(
                        type: "string",
                        description: "Arithmetic expression to evaluate."
                    )
                ],
                required: ["expression"]
            )
        case "fetch_url":
            return ToolParametersSchema(
                properties: [
                    "url": ToolPropertySchema(type: "string", description: "HTTP or HTTPS URL to fetch."),
                    "timeout_seconds": ToolPropertySchema(type: "number", description: "Optional request timeout in seconds.")
                ],
                required: ["url"]
            )
        case "web_search":
            return ToolParametersSchema(
                properties: [
                    "query": ToolPropertySchema(type: "string", description: "Search query string.")
                ],
                required: ["query"]
            )
        case "calendar_list_events":
            return ToolParametersSchema(
                properties: [
                    "calendar_id": ToolPropertySchema(type: "string", description: "Optional calendar identifier to filter by."),
                    "start_date": ToolPropertySchema(type: "string", description: "Inclusive ISO-8601 start date."),
                    "end_date": ToolPropertySchema(type: "string", description: "Inclusive ISO-8601 end date.")
                ]
            )
        case "calendar_get_event", "calendar_delete_event":
            return ToolParametersSchema(
                properties: [
                    "event_id": ToolPropertySchema(type: "string", description: "Calendar event identifier.")
                ],
                required: ["event_id"]
            )
        case "calendar_create_event":
            return ToolParametersSchema(
                properties: [
                    "title": ToolPropertySchema(type: "string", description: "Event title."),
                    "start_date": ToolPropertySchema(type: "string", description: "ISO-8601 event start."),
                    "end_date": ToolPropertySchema(type: "string", description: "ISO-8601 event end."),
                    "calendar_id": ToolPropertySchema(type: "string", description: "Destination calendar identifier."),
                    "location": ToolPropertySchema(type: "string", description: "Optional event location."),
                    "notes": ToolPropertySchema(type: "string", description: "Optional event notes.")
                ],
                required: ["title", "start_date", "end_date"]
            )
        case "calendar_update_event":
            return ToolParametersSchema(
                properties: [
                    "event_id": ToolPropertySchema(type: "string", description: "Calendar event identifier."),
                    "title": ToolPropertySchema(type: "string", description: "Updated event title."),
                    "start_date": ToolPropertySchema(type: "string", description: "Updated ISO-8601 event start."),
                    "end_date": ToolPropertySchema(type: "string", description: "Updated ISO-8601 event end."),
                    "location": ToolPropertySchema(type: "string", description: "Updated event location."),
                    "notes": ToolPropertySchema(type: "string", description: "Updated event notes.")
                ],
                required: ["event_id"]
            )
        case "reminders_list":
            return ToolParametersSchema(
                properties: [
                    "list_id": ToolPropertySchema(type: "string", description: "Optional reminders list identifier."),
                    "completed": ToolPropertySchema(type: "boolean", description: "Optional completion-state filter.")
                ]
            )
        case "reminders_get", "reminders_delete", "reminders_complete", "reminders_uncomplete":
            return ToolParametersSchema(
                properties: [
                    "reminder_id": ToolPropertySchema(type: "string", description: "Reminder identifier.")
                ],
                required: ["reminder_id"]
            )
        case "reminders_create":
            return ToolParametersSchema(
                properties: [
                    "title": ToolPropertySchema(type: "string", description: "Reminder title."),
                    "list_id": ToolPropertySchema(type: "string", description: "Optional reminders list identifier."),
                    "due_date": ToolPropertySchema(type: "string", description: "Optional ISO-8601 due date."),
                    "priority": ToolPropertySchema(type: "integer", description: "Optional reminder priority."),
                    "notes": ToolPropertySchema(type: "string", description: "Optional reminder notes.")
                ],
                required: ["title"]
            )
        case "reminders_update":
            return ToolParametersSchema(
                properties: [
                    "reminder_id": ToolPropertySchema(type: "string", description: "Reminder identifier."),
                    "title": ToolPropertySchema(type: "string", description: "Updated reminder title."),
                    "due_date": ToolPropertySchema(type: "string", description: "Updated ISO-8601 due date."),
                    "priority": ToolPropertySchema(type: "integer", description: "Updated reminder priority."),
                    "notes": ToolPropertySchema(type: "string", description: "Updated reminder notes.")
                ],
                required: ["reminder_id"]
            )
        case "reminders_list_create":
            return ToolParametersSchema(
                properties: [
                    "title": ToolPropertySchema(type: "string", description: "New reminders list title.")
                ],
                required: ["title"]
            )
        case "reminders_list_delete":
            return ToolParametersSchema(
                properties: [
                    "list_id": ToolPropertySchema(type: "string", description: "Reminders list identifier.")
                ],
                required: ["list_id"]
            )
        case "reminders_list_rename":
            return ToolParametersSchema(
                properties: [
                    "list_id": ToolPropertySchema(type: "string", description: "Reminders list identifier."),
                    "new_title": ToolPropertySchema(type: "string", description: "Replacement list title.")
                ],
                required: ["list_id", "new_title"]
            )
        case "spawn_sub_agent":
            return ToolParametersSchema(
                properties: [
                    "task": ToolPropertySchema(type: "string", description: "Focused task for the sub-agent."),
                    "type": ToolPropertySchema(type: "string", description: "Sub-agent type.", enumValues: ["research", "summarize", "verify"]),
                    "steps": ToolPropertySchema(type: "integer", description: "Optional max step count from 1 to 15.")
                ],
                required: ["task"]
            )
        case "shortcuts_run":
            return ToolParametersSchema(
                properties: [
                    "shortcut_name": ToolPropertySchema(type: "string", description: "Shortcut name to run."),
                    "input": ToolPropertySchema(type: "string", description: "Optional text input for the shortcut.")
                ],
                required: ["shortcut_name"]
            )
        default:
            return nil
        }
    }
}
