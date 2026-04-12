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

    /// Generate only the tool definitions that can actually run in the current runtime context.
    public func availableDefinitions(for context: ToolContext) -> [ToolDefinition] {
        allTools
            .filter { Self.isDefinitionAvailable(named: type(of: $0).name, context: context) }
            .map { tool in
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

    private static let databaseBackedTools: Set<String> = [
        "bookshelf_lookup",
        "notes_search",
        "reading_history",
        "semantic_search_library",
        "tags_list",
        "books_tags_list",
        "apply_book_tags",
    ]

    private static let activeBookTools: Set<String> = [
        "current_reading_metadata",
        "create_highlight",
        "create_note",
    ]

    private static let readerSessionTools: Set<String> = [
        "current_book_toc",
        "current_book_fulltext",
        "chapter_content_by_href",
        "book_content_search",
    ]

    private static let readerSessionLocationTools: Set<String> = [
        "current_chapter_content",
    ]

    private static let hiddenReaderSessionTools: Set<String> = [
        "resolve_cfi",
        "semantic_search_current_book",
    ]

    private static let memoryTools: Set<String> = [
        "memory_read",
        "memory_write",
        "memory_search",
    ]

    private static let calendarTools: Set<String> = [
        "calendar_list_calendars",
        "calendar_list_events",
        "calendar_get_event",
        "calendar_create_event",
        "calendar_update_event",
        "calendar_delete_event",
    ]

    private static let remindersTools: Set<String> = [
        "reminders_list_lists",
        "reminders_list",
        "reminders_get",
        "reminders_create",
        "reminders_update",
        "reminders_complete",
        "reminders_uncomplete",
        "reminders_delete",
        "reminders_list_create",
        "reminders_list_rename",
        "reminders_list_delete",
    ]

    private static func isDefinitionAvailable(named name: String, context: ToolContext) -> Bool {
        switch name {
        case "spawn_sub_agent":
            return context.subAgentService != nil
        case "shortcuts_run":
            return context.shortcutsService != nil
        default:
            break
        }

        if memoryTools.contains(name) {
            return context.memoryDirectory != nil
        }
        if calendarTools.contains(name) {
            return context.calendarService != nil
        }
        if remindersTools.contains(name) {
            return context.remindersService != nil
        }
        if databaseBackedTools.contains(name) {
            return context.database != nil
        }
        if activeBookTools.contains(name) {
            return context.activeBookId != nil && context.database != nil
        }
        if hiddenReaderSessionTools.contains(name) {
            return false
        }
        if readerSessionLocationTools.contains(name) {
            return context.hasBookContentBridge && (context.currentChapterHref?.isEmpty == false)
        }
        if readerSessionTools.contains(name) {
            return context.hasBookContentBridge
        }
        return true
    }

    private static func schema(forToolNamed name: String) -> ToolParametersSchema? {
        let empty = ToolParametersSchema(properties: [:])
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
        case "mindmap_draw":
            return ToolParametersSchema(
                properties: [
                    "content": ToolPropertySchema(type: "string", description: "Hierarchical bullet list content to convert into a mindmap JSON.")
                ],
                required: ["content"]
            )
        case "current_time":
            return empty
        case "tool_approval_decider":
            return ToolParametersSchema(
                properties: [
                    "tool_name": ToolPropertySchema(type: "string", description: "Name of the tool being considered."),
                    "risk_level": ToolPropertySchema(type: "string", description: "Risk level string for the pending tool call.", enumValues: ["safe", "moderate", "dangerous"])
                ]
            )
        case "bookshelf_lookup":
            return ToolParametersSchema(
                properties: [
                    "query": ToolPropertySchema(type: "string", description: "Optional title/author keyword query."),
                    "group_id": ToolPropertySchema(type: "integer", description: "Optional bookshelf group identifier."),
                    "limit": ToolPropertySchema(type: "integer", description: "Optional max results (default 20).")
                ]
            )
        case "bookshelf_organize":
            return ToolParametersSchema(
                properties: [
                    "moves": ToolPropertySchema(type: "array", description: "Optional list of proposed book moves. Each item should include book identifiers and destination group."),
                    "renames": ToolPropertySchema(type: "array", description: "Optional list of proposed group renames.")
                ]
            )
        case "books_tags_list":
            return empty
        case "tags_list":
            return empty
        case "apply_book_tags":
            return ToolParametersSchema(
                properties: [
                    "changes": ToolPropertySchema(type: "array", description: "List of tag changes to apply. Each item should include book id and tags to add/remove.")
                ]
            )
        case "current_reading_metadata":
            return empty
        case "current_book_toc":
            return empty
        case "current_chapter_content":
            return ToolParametersSchema(
                properties: [
                    "href": ToolPropertySchema(type: "string", description: "Optional TOC href to fetch instead of the currently active chapter.")
                ]
            )
        case "current_book_fulltext":
            return empty
        case "chapter_content_by_href":
            return ToolParametersSchema(
                properties: [
                    "href": ToolPropertySchema(type: "string", description: "TOC href identifier for the chapter.")
                ],
                required: ["href"]
            )
        case "resolve_cfi":
            return ToolParametersSchema(
                properties: [
                    "cfi": ToolPropertySchema(type: "string", description: "EPUB CFI locator string to resolve.")
                ],
                required: ["cfi"]
            )
        case "book_content_search":
            return ToolParametersSchema(
                properties: [
                    "query": ToolPropertySchema(type: "string", description: "Full-text search query for the current book.")
                ],
                required: ["query"]
            )
        case "create_highlight":
            return ToolParametersSchema(
                properties: [
                    "cfi": ToolPropertySchema(type: "string", description: "EPUB CFI locator where the highlight is anchored."),
                    "content": ToolPropertySchema(type: "string", description: "Highlighted text content."),
                    "color": ToolPropertySchema(type: "string", description: "Optional highlight color name.", enumValues: ["yellow", "green", "blue", "red", "purple"]),
                    "chapter": ToolPropertySchema(type: "string", description: "Optional chapter title for context.")
                ],
                required: ["cfi", "content"]
            )
        case "create_note":
            return ToolParametersSchema(
                properties: [
                    "cfi": ToolPropertySchema(type: "string", description: "EPUB CFI locator where the note is anchored."),
                    "content": ToolPropertySchema(type: "string", description: "Selected text (or context) at the note position."),
                    "chapter": ToolPropertySchema(type: "string", description: "Optional chapter title for context."),
                    "reader_note": ToolPropertySchema(type: "string", description: "Optional freeform note text written by the user.")
                ],
                required: ["cfi", "content"]
            )
        case "notes_search":
            return ToolParametersSchema(
                properties: [
                    "keyword": ToolPropertySchema(type: "string", description: "Optional keyword to search within notes."),
                    "book_id": ToolPropertySchema(type: "integer", description: "Optional book identifier to filter notes by."),
                    "limit": ToolPropertySchema(type: "integer", description: "Optional max results (default 20).")
                ]
            )
        case "reading_history":
            return ToolParametersSchema(
                properties: [
                    "book_id": ToolPropertySchema(type: "integer", description: "Optional book identifier to filter reading sessions by.")
                ]
            )
        case "semantic_search_current_book":
            return empty
        case "semantic_search_library":
            return empty
        case "calendar_list_calendars":
            return empty
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
        case "reminders_list_lists":
            return empty
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
                    "agentType": ToolPropertySchema(type: "string", description: "Alias for 'type'.", enumValues: ["research", "summarize", "verify"]),
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
        case "memory_read":
            return ToolParametersSchema(
                properties: [
                    "filename": ToolPropertySchema(type: "string", description: "Optional memory filename to read (default MEMORY.md).")
                ]
            )
        case "memory_write":
            return ToolParametersSchema(
                properties: [
                    "content": ToolPropertySchema(type: "string", description: "Markdown content to write or append."),
                    "filename": ToolPropertySchema(type: "string", description: "Optional memory filename to write (default MEMORY.md)."),
                    "append": ToolPropertySchema(type: "boolean", description: "Whether to append if file exists (default true).")
                ],
                required: ["content"]
            )
        case "memory_search":
            return ToolParametersSchema(
                properties: [
                    "keyword": ToolPropertySchema(type: "string", description: "Optional keyword to search within memory files. Empty means list all.")
                ]
            )
        default:
            return nil
        }
    }
}
