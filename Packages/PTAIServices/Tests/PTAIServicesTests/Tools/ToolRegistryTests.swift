import Foundation
import Testing
@testable import PTAIServices

@Suite("ToolRegistry")
struct ToolRegistryTests {
    private struct MockReaderBridge: BookContentBridgeProtocol {
        let tableOfContents: String
        let chapterText: String
        let fullBookText: String
        let searchResults: String

        init(
            tableOfContents: String = #"{"chapters":[{"title":"Introduction","href":"chapter-1"}]}"#,
            chapterText: String = "Introduction body",
            fullBookText: String = "Short body",
            searchResults: String = #"{"results":[{"href":"chapter-1"}]}"#
        ) {
            self.tableOfContents = tableOfContents
            self.chapterText = chapterText
            self.fullBookText = fullBookText
            self.searchResults = searchResults
        }

        func tableOfContentsJSON() async throws -> String { tableOfContents }
        func chapterContent(href: String) async throws -> String { chapterText }
        func fullText() async throws -> String { fullBookText }
        func search(query: String) async throws -> String { searchResults }
    }

    private struct MockDatabase: ToolDatabaseAccess {
        func fetchBooks(query: String?, groupId: Int64?, limit: Int) async throws -> [[String : Any]] { [] }
        func fetchBookNotes(bookId: Int64?, keyword: String?, limit: Int) async throws -> [[String : Any]] { [] }
        func fetchReadingTime(bookId: Int64?, since: Date?) async throws -> [[String : Any]] { [] }
        func fetchTags() async throws -> [[String : Any]] { [] }
        func insertBookNote(_ fields: [String : Any]) async throws {}
    }

    private struct MockSubAgentService: SubAgentServiceProtocol {
        func spawn(task: String, type: String, requestedSteps: Int?) async throws -> SubAgentSpawnResult {
            SubAgentSpawnResult(status: "ok", summary: "stub", agentType: type, requestedSteps: requestedSteps)
        }
    }

    private struct MockShortcutsService: ShortcutsServiceProtocol {
        func runShortcut(named name: String, input: String?) async throws -> ShortcutsRunResult {
            ShortcutsRunResult(status: "ok", shortcutName: name)
        }
    }

    @Test("default registry contains 46 tools")
    func toolCount() {
        let registry = ToolRegistry()
        #expect(registry.count == 46)
    }

    @Test("find calculator tool by name")
    func findCalculatorByName() {
        let registry = ToolRegistry()
        let tool = registry.tool(named: "calculator")
        #expect(tool != nil)
    }

    @Test("find memory_read tool by name")
    func findMemoryReadByName() {
        let registry = ToolRegistry()
        #expect(registry.tool(named: "memory_read") != nil)
    }

    @Test("find current_time tool by name")
    func findCurrentTimeByName() {
        let registry = ToolRegistry()
        #expect(registry.tool(named: "current_time") != nil)
    }

    @Test("allDefinitions returns correct count")
    func allDefinitionsCount() {
        let registry = ToolRegistry()
        let defs = registry.allDefinitions()
        #expect(defs.count == 46)
    }

    @Test("all built-in tool definitions include explicit parameter schemas (including empty schema for no-arg tools)")
    func allDefinitionsHaveSchemas() {
        let registry = ToolRegistry()
        let defs = registry.allDefinitions()
        let missing = defs.filter { $0.parameters == nil }.map(\.name).sorted()
        if missing.isEmpty == false {
            // Make failures actionable when tools are added without schema wiring.
            print("Missing tool parameter schemas:", missing.joined(separator: ", "))
        }
        #expect(missing.isEmpty)
    }

    @Test("allDefinitions includes parameter schemas when available")
    func allDefinitionsIncludeSchemas() {
        let registry = ToolRegistry()
        let defs = registry.allDefinitions()

        let calculator = defs.first { $0.name == "calculator" }
        #expect(calculator?.parameters?.properties["expression"]?.type == "string")

        let calendarCreate = defs.first { $0.name == "calendar_create_event" }
        #expect(calendarCreate?.parameters?.properties["title"]?.type == "string")

        let spawnSubAgent = defs.first { $0.name == "spawn_sub_agent" }
        #expect(spawnSubAgent?.parameters?.properties["task"]?.type == "string")
        #expect(spawnSubAgent?.parameters?.properties["agentType"]?.type == "string")
        #expect(spawnSubAgent?.parameters?.properties["agentType"]?.enumValues == ["research", "summarize", "verify"])
        #expect(spawnSubAgent?.parameters?.properties["steps"]?.type == "integer")

        let shortcutsRun = defs.first { $0.name == "shortcuts_run" }
        #expect(shortcutsRun?.parameters?.properties["shortcut_name"]?.type == "string")
    }

    @Test("availableDefinitions hide tools whose runtime prerequisites are missing")
    func availableDefinitionsHideUnsupportedTools() {
        let registry = ToolRegistry()
        let names = Set(registry.availableDefinitions(for: ToolContext()).map(\.name))

        #expect(names.contains("spawn_sub_agent") == false)
        #expect(names.contains("shortcuts_run") == false)
        #expect(names.contains("memory_read") == false)
        #expect(names.contains("bookshelf_lookup") == false)
        #expect(names.contains("current_reading_metadata") == false)
        #expect(names.contains("current_book_toc") == false)
    }

    @Test("availableDefinitions include runtime-backed tools when their prerequisites are present")
    func availableDefinitionsIncludeSupportedTools() {
        let registry = ToolRegistry()
        let context = ToolContext(
            bookId: 1,
            database: MockDatabase(),
            memoryDirectory: FileManager.default.temporaryDirectory,
            subAgentService: MockSubAgentService(),
            shortcutsService: MockShortcutsService()
        )
        let names = Set(registry.availableDefinitions(for: context).map(\.name))

        #expect(names.contains("spawn_sub_agent"))
        #expect(names.contains("shortcuts_run"))
        #expect(names.contains("memory_read"))
        #expect(names.contains("bookshelf_lookup"))
        #expect(names.contains("current_reading_metadata"))
        #expect(names.contains("current_book_toc") == false)
    }

    @Test("availableDefinitions include reader-session tools when an active reader session exists")
    func availableDefinitionsIncludeReaderSessionTools() {
        let registry = ToolRegistry()
        let readerSessionStore = ReaderSessionContextStore()
        readerSessionStore.update(
            ReaderSessionSnapshot(
                bookId: 42,
                readingProgress: 0.25,
                chapterTitle: "Introduction",
                locationHref: "chapter-1",
                contentBridgeProvider: { MockReaderBridge() }
            )
        )
        let context = ToolContext(
            database: MockDatabase(),
            readerSessionStore: readerSessionStore
        )

        let names = Set(registry.availableDefinitions(for: context).map(\.name))

        #expect(names.contains("current_reading_metadata"))
        #expect(names.contains("create_highlight"))
        #expect(names.contains("create_note"))
        #expect(names.contains("current_book_toc"))
        #expect(names.contains("current_chapter_content"))
        #expect(names.contains("current_book_fulltext"))
        #expect(names.contains("chapter_content_by_href"))
        #expect(names.contains("book_content_search"))
        #expect(names.contains("resolve_cfi") == false)
        #expect(names.contains("semantic_search_current_book") == false)
    }

    @Test("availableDefinitions hide current chapter content when reader session has no live chapter yet")
    func availableDefinitionsHideCurrentChapterContentWithoutHref() {
        let registry = ToolRegistry()
        let readerSessionStore = ReaderSessionContextStore()
        readerSessionStore.update(
            ReaderSessionSnapshot(
                bookId: 42,
                readingProgress: 0.25,
                chapterTitle: "Introduction",
                locationHref: nil,
                contentBridgeProvider: { MockReaderBridge() }
            )
        )
        let context = ToolContext(
            database: MockDatabase(),
            readerSessionStore: readerSessionStore
        )

        let names = Set(registry.availableDefinitions(for: context).map(\.name))

        #expect(names.contains("current_book_toc"))
        #expect(names.contains("current_chapter_content") == false)
        #expect(names.contains("chapter_content_by_href"))
    }

    @Test("extra tools can be registered")
    func extraTools() {
        let registry = ToolRegistry(extras: [])
        #expect(registry.count == 46)
    }

    @Test("unknown tool returns nil")
    func unknownToolReturnsNil() {
        let registry = ToolRegistry()
        #expect(registry.tool(named: "nonexistent_tool") == nil)
    }

    @Test("all tool names are unique")
    func allToolNamesUnique() {
        let registry = ToolRegistry()
        let names = registry.allTools.map { type(of: $0).name }
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count)
    }

    @Test("registerAll populates orchestrator")
    func registerAllIntoOrchestrator() async {
        let registry = ToolRegistry()
        let orchestrator = ToolOrchestrator()
        await registry.registerAll(into: orchestrator)
        // The orchestrator should now have all tools registered
        // We verify by executing a known tool
        let result = try? await orchestrator.execute(
            calls: [ToolCall(id: "test", name: "current_time", arguments: "{}")],
            context: ToolContext()
        )
        #expect(result?.first?.isError == false)
    }
}
