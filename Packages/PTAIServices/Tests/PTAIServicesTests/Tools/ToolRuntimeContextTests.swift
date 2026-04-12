import Foundation
import Testing
@testable import PTAIServices

@Suite("Tool runtime context")
struct ToolRuntimeContextTests {
    final class RecordingDatabase: ToolDatabaseAccess, @unchecked Sendable {
        struct InsertedNote: Sendable {
            let bookId: Int64
            let content: String
            let cfi: String
            let color: String
            let type: String
            let chapter: String
            let readerNote: String
        }

        private let queue = DispatchQueue(label: "ToolRuntimeContextTests.RecordingDatabase")
        private let books: [[String: Any]]
        private let booksByID: [Int64: [String: Any]]
        private let onFetchBooks: (@Sendable () -> Void)?
        private let onFetchBook: (@Sendable (Int64) -> Void)?
        private var insertedNotes: [InsertedNote] = []

        init(
            books: [[String: Any]] = [],
            booksByID: [Int64: [String: Any]] = [:],
            onFetchBooks: (@Sendable () -> Void)? = nil,
            onFetchBook: (@Sendable (Int64) -> Void)? = nil
        ) {
            self.books = books
            self.booksByID = booksByID
            self.onFetchBooks = onFetchBooks
            self.onFetchBook = onFetchBook
        }

        func fetchBooks(query: String?, groupId: Int64?, limit: Int) async throws -> [[String : Any]] {
            onFetchBooks?()
            return books
        }

        func fetchBook(id: Int64) async throws -> [String : Any]? {
            onFetchBook?(id)
            return booksByID[id] ?? books.first { ($0["id"] as? Int64) == id }
        }

        func fetchBookNotes(bookId: Int64?, keyword: String?, limit: Int) async throws -> [[String : Any]] {
            []
        }

        func fetchReadingTime(bookId: Int64?, since: Date?) async throws -> [[String : Any]] {
            []
        }

        func fetchTags() async throws -> [[String : Any]] {
            []
        }

        func insertBookNote(_ fields: [String : Any]) async throws {
            let note = InsertedNote(
                bookId: fields["book_id"] as? Int64 ?? -1,
                content: fields["content"] as? String ?? "",
                cfi: fields["cfi"] as? String ?? "",
                color: fields["color"] as? String ?? "",
                type: fields["type"] as? String ?? "",
                chapter: fields["chapter"] as? String ?? "",
                readerNote: fields["reader_note"] as? String ?? ""
            )
            queue.sync {
                insertedNotes.append(note)
            }
        }

        var lastInsertedNote: InsertedNote? {
            queue.sync {
                insertedNotes.last
            }
        }
    }

    struct MockReaderBridge: BookContentBridgeProtocol {
        let tableOfContents: String
        let chapterText: String
        let fullBookText: String
        let searchResults: String

        init(
            tableOfContents: String = #"{"chapters":[{"title":"Introduction","href":"chapter-1"}]}"#,
            chapterText: String = "Chapter 1 text",
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

    struct StrictReaderBridge: BookContentBridgeProtocol {
        let expectedHref: String
        let chapterText: String

        func tableOfContentsJSON() async throws -> String { "{}" }

        func chapterContent(href: String) async throws -> String {
            if href == expectedHref {
                return chapterText
            }
            struct UnexpectedHrefError: Error {}
            throw UnexpectedHrefError()
        }

        func fullText() async throws -> String { chapterText }
        func search(query: String) async throws -> String { "{}" }
    }

    final class MockCalendarService: CalendarServiceProtocol, @unchecked Sendable {
        func listCalendars() async throws -> [[String : Any]] {
            [["id": "cal-1", "title": "Work"]]
        }

        func listEvents(calendarId: String?, startDate: Date, endDate: Date) async throws -> [[String : Any]] {
            []
        }

        func getEvent(eventId: String) async throws -> [String : Any] {
            [:]
        }

        func createEvent(_ params: [String : Any]) async throws -> [String : Any] {
            [:]
        }

        func updateEvent(eventId: String, params: [String : Any]) async throws -> [String : Any] {
            [:]
        }

        func deleteEvent(eventId: String) async throws {}
    }

    final class MockRemindersService: RemindersServiceProtocol, @unchecked Sendable {
        func listLists() async throws -> [[String : Any]] {
            [["id": "list-1", "title": "Inbox"]]
        }

        func listReminders(listId: String?, completed: Bool?) async throws -> [[String : Any]] {
            []
        }

        func getReminder(reminderId: String) async throws -> [String : Any] {
            [:]
        }

        func createReminder(_ params: [String : Any]) async throws -> [String : Any] {
            [:]
        }

        func updateReminder(id: String, params: [String : Any]) async throws -> [String : Any] {
            [:]
        }

        func deleteReminder(id: String) async throws {}

        func completeReminder(id: String) async throws {}

        func uncompleteReminder(id: String) async throws {}

        func createList(title: String) async throws -> [String : Any] {
            [:]
        }

        func deleteList(id: String) async throws {}

        func renameList(id: String, newTitle: String) async throws {}
    }

    struct MockSubAgentService: SubAgentServiceProtocol {
        func spawn(task: String, type: String, requestedSteps: Int?) async throws -> SubAgentSpawnResult {
            SubAgentSpawnResult(
                status: "completed",
                summary: "summarized \(task)",
                agentType: type,
                requestedSteps: requestedSteps
            )
        }
    }

    struct MockShortcutsService: ShortcutsServiceProtocol {
        func runShortcut(named name: String, input: String?) async throws -> ShortcutsRunResult {
            ShortcutsRunResult(
                status: "opened",
                shortcutName: name,
                detail: input ?? "no-input"
            )
        }
    }

    private func jsonObject(_ string: String) -> [String: Any] {
        let data = Data(string.utf8)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @Test("calendar tools read calendar service from ToolContext")
    func calendarToolUsesContextService() async throws {
        let result = try await CalendarListCalendarsTool().execute(
            arguments: [:],
            context: ToolContext(calendarService: MockCalendarService())
        )

        let payload = jsonObject(result.content)
        let calendars = payload["calendars"] as? [[String: Any]]
        #expect(calendars?.count == 1)
        #expect(calendars?.first?["id"] as? String == "cal-1")
    }

    @Test("reminders tools read reminders service from ToolContext")
    func remindersToolUsesContextService() async throws {
        let result = try await RemindersListListsTool().execute(
            arguments: [:],
            context: ToolContext(remindersService: MockRemindersService())
        )

        let payload = jsonObject(result.content)
        let lists = payload["lists"] as? [[String: Any]]
        #expect(lists?.count == 1)
        #expect(lists?.first?["id"] as? String == "list-1")
    }

    @Test("spawn_sub_agent returns typed unsupported result without runtime")
    func spawnSubAgentUnsupportedWithoutRuntime() async throws {
        let result = try await SpawnSubAgentTool().execute(
            arguments: ["task": "summarize", "type": "research"],
            context: ToolContext()
        )

        let payload = jsonObject(result.content)
        #expect(result.isError)
        #expect(payload["status"] as? String == "unsupported")
        #expect(payload["requires"] as? String == "subAgentService")
    }

    @Test("spawn_sub_agent uses ToolContext runtime when available")
    func spawnSubAgentUsesRuntime() async throws {
        let result = try await SpawnSubAgentTool().execute(
            arguments: ["task": "summarize chapter 1", "type": "research", "steps": 3],
            context: ToolContext(subAgentService: MockSubAgentService())
        )

        let payload = jsonObject(result.content)
        #expect(result.isError == false)
        #expect(payload["status"] as? String == "completed")
        #expect(payload["agent_type"] as? String == "research")
    }

    @Test("shortcuts_run returns typed unsupported result without runtime")
    func shortcutsRunUnsupportedWithoutRuntime() async throws {
        let result = try await ShortcutsRunTool().execute(
            arguments: ["shortcut_name": "Morning Routine"],
            context: ToolContext()
        )

        let payload = jsonObject(result.content)
        #expect(result.isError)
        #expect(payload["status"] as? String == "unsupported")
        #expect(payload["requires"] as? String == "shortcutsService")
    }

    @Test("shortcuts_run uses ToolContext runtime when available")
    func shortcutsRunUsesRuntime() async throws {
        let result = try await ShortcutsRunTool().execute(
            arguments: ["shortcut_name": "Morning Routine", "input": "today"],
            context: ToolContext(shortcutsService: MockShortcutsService())
        )

        let payload = jsonObject(result.content)
        #expect(result.isError == false)
        #expect(payload["status"] as? String == "opened")
        #expect(payload["shortcut_name"] as? String == "Morning Routine")
    }

    @Test("reader-session tools execute through ToolContext reader session store")
    func readerSessionToolsUseContextStore() async throws {
        let readerSessionStore = ReaderSessionContextStore()
        readerSessionStore.update(
            ReaderSessionSnapshot(
                bookId: 9,
                readingProgress: 0.4,
                chapterTitle: "Introduction",
                locationHref: "chapter-1",
                contentBridgeProvider: { MockReaderBridge() }
            )
        )
        let orchestrator = ToolOrchestrator()
        await ToolRegistry().registerAll(into: orchestrator)

        let results = try await orchestrator.execute(
            calls: [
                ToolCall(id: "toc", name: "current_book_toc", arguments: "{}"),
                ToolCall(id: "chapter", name: "current_chapter_content", arguments: "{}"),
            ],
            context: ToolContext(readerSessionStore: readerSessionStore)
        )

        #expect(results.count == 2)
        #expect(results[0].isError == false)
        #expect(results[0].content.contains("Introduction"))
        #expect(results[1].isError == false)
        #expect(results[1].content == "Chapter 1 text")
    }

    @Test("current_book_fulltext rejects content longer than fifty thousand characters")
    func currentBookFulltextRejectsOversizedBooks() async throws {
        let readerSessionStore = ReaderSessionContextStore()
        readerSessionStore.update(
            ReaderSessionSnapshot(
                bookId: 9,
                readingProgress: 0.4,
                chapterTitle: "Introduction",
                locationHref: "chapter-1",
                contentBridgeProvider: {
                    MockReaderBridge(fullBookText: String(repeating: "a", count: 50_001))
                }
            )
        )

        let result = try await CurrentBookFulltextTool().execute(
            arguments: [:],
            context: ToolContext(readerSessionStore: readerSessionStore)
        )

        #expect(result.isError)
    }

    @Test("annotation tools use active reader-session book id when static book id is absent")
    func annotationToolsUseActiveReaderSessionBookId() async throws {
        let database = RecordingDatabase()
        let readerSessionStore = ReaderSessionContextStore()
        readerSessionStore.update(
            ReaderSessionSnapshot(bookId: 91)
        )

        let highlightResult = try await CreateHighlightTool().execute(
            arguments: [
                "cfi": "epubcfi(/6/2[chapter-1]!/4/2/6)",
                "content": "Highlighted passage",
                "chapter": "Introduction",
            ],
            context: ToolContext(database: database, readerSessionStore: readerSessionStore)
        )

        let noteResult = try await CreateNoteTool().execute(
            arguments: [
                "cfi": "epubcfi(/6/2[chapter-1]!/4/2/8)",
                "content": "Note anchor",
                "reader_note": "My margin note",
            ],
            context: ToolContext(database: database, readerSessionStore: readerSessionStore)
        )

        #expect(highlightResult.isError == false)
        #expect(noteResult.isError == false)
        #expect(database.lastInsertedNote?.bookId == 91)
    }

    @Test("current chapter content uses a single reader snapshot")
    func currentChapterContentUsesSingleSnapshot() async throws {
        let readerSessionStore = ReaderSessionContextStore()
        let secondSnapshot = ReaderSessionSnapshot(
            bookId: 2,
            readingProgress: 0.8,
            chapterTitle: "Chapter Two",
            locationHref: "chapter-2",
            contentBridgeProvider: { StrictReaderBridge(expectedHref: "chapter-2", chapterText: "Chapter 2 text") }
        )
        readerSessionStore.update(
            ReaderSessionSnapshot(
                bookId: 1,
                readingProgress: 0.2,
                chapterTitle: "Chapter One",
                locationHref: "chapter-1",
                contentBridgeProvider: {
                    readerSessionStore.update(secondSnapshot)
                    return StrictReaderBridge(expectedHref: "chapter-1", chapterText: "Chapter 1 text")
                }
            )
        )

        let result = try await CurrentChapterContentTool().execute(
            arguments: [:],
            context: ToolContext(readerSessionStore: readerSessionStore)
        )

        #expect(result.isError == false)
        #expect(result.content == "Chapter 1 text")
    }

    @Test("current reading metadata uses a single reader snapshot")
    func currentReadingMetadataUsesSingleSnapshot() async throws {
        let readerSessionStore = ReaderSessionContextStore()
        let database = RecordingDatabase(
            books: [
                ["id": Int64(7), "title": "Book Seven"],
                ["id": Int64(8), "title": "Book Eight"],
            ],
            onFetchBook: { _ in
                readerSessionStore.update(
                    ReaderSessionSnapshot(
                        bookId: 8,
                        readingProgress: 0.9,
                        chapterTitle: "Other Chapter",
                        locationHref: "chapter-8"
                    )
                )
            }
        )
        readerSessionStore.update(
            ReaderSessionSnapshot(
                bookId: 7,
                readingProgress: 0.4,
                chapterTitle: "Intro",
                locationHref: "chapter-7"
            )
        )

        let result = try await CurrentReadingMetadataTool().execute(
            arguments: [:],
            context: ToolContext(database: database, readerSessionStore: readerSessionStore)
        )

        let payload = jsonObject(result.content)
        let book = payload["book"] as? [String: Any]
        #expect(book?["id"] as? Int64 == 7)
        #expect(payload["progress"] as? Double == 0.4)
        #expect(payload["chapter_title"] as? String == "Intro")
    }

    @Test("current reading metadata does not depend on paginated fetchBooks results")
    func currentReadingMetadataBypassesPagination() async throws {
        let allBooks = (1...250).map { index in
            [
                "id": Int64(index),
                "title": "Book \(index)",
            ] as [String: Any]
        }
        let database = RecordingDatabase(
            books: Array(allBooks.prefix(200)),
            booksByID: [250: ["id": Int64(250), "title": "Book 250"]]
        )
        let readerSessionStore = ReaderSessionContextStore()
        readerSessionStore.update(
            ReaderSessionSnapshot(
                bookId: 250,
                readingProgress: 0.25,
                chapterTitle: "Final Chapter",
                locationHref: "chapter-250"
            )
        )

        let result = try await CurrentReadingMetadataTool().execute(
            arguments: [:],
            context: ToolContext(database: database, readerSessionStore: readerSessionStore)
        )

        let payload = jsonObject(result.content)
        let book = payload["book"] as? [String: Any]
        #expect(book?["id"] as? Int64 == 250)
        #expect(book?["title"] as? String == "Book 250")
    }

    @Test("current book fulltext oversize error points to available search tooling")
    func currentBookFulltextOversizeMessagePointsToAvailableTooling() async throws {
        let readerSessionStore = ReaderSessionContextStore()
        readerSessionStore.update(
            ReaderSessionSnapshot(
                bookId: 9,
                contentBridgeProvider: {
                    MockReaderBridge(fullBookText: String(repeating: "a", count: 50_001))
                }
            )
        )

        let result = try await CurrentBookFulltextTool().execute(
            arguments: [:],
            context: ToolContext(readerSessionStore: readerSessionStore)
        )

        #expect(result.isError)
        #expect(result.content.contains("book_content_search"))
        #expect(result.content.contains("semantic_search_current_book") == false)
    }
}
