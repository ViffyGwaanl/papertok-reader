import Foundation
import Testing
@testable import PTFeatures
import PTCore
import PTReader
import PTAIServices

@Suite("ContextMenuCoordinator")
@MainActor
struct ContextMenuCoordinatorTests {
    struct StaticTranslationProvider: ChatModelProvider {
        let id: String = "translation-mock"
        let displayName: String = "Translation Mock"
        let supportedCapabilities: Set<ModelCapability> = [.chat]

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(message: .assistant("translated"))
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    @Test("saveExcerptToNotes persists an annotation note instead of a highlight")
    func saveExcerptToNotesPersistsNoteType() async throws {
        let database = try AppDatabase.makeInMemory()
        let noteDAO = BookNoteDAO(database: database)
        let bookID = try await insertBook(title: "Context Menu Book", database: database)
        let coordinator = ContextMenuCoordinator(
            bookId: bookID,
            bookTitle: "Context Menu Book",
            bookAuthor: "PaperTok",
            database: database
        )

        coordinator.showMenu(
            text: "A passage worth revisiting",
            locator: #"{"href":"chapter-1.xhtml"}"#,
            chapter: "Chapter 1"
        )
        await coordinator.saveExcerptToNotes()

        let persisted = try await noteDAO.fetchByBookId(bookID)
        #expect(persisted.count == 1)
        #expect(persisted[0].type == NoteType.note.rawValue)
        #expect(persisted[0].content == "A passage worth revisiting")
        #expect(coordinator.activeSheet == nil)
    }

    @Test("search action stages the selected text as a pending query and dismisses the menu")
    func searchActionStagesPendingQuery() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "Searchable Book", database: database)
        let coordinator = ContextMenuCoordinator(
            bookId: bookID,
            bookTitle: "Searchable Book",
            bookAuthor: "PaperTok",
            database: database
        )

        coordinator.showMenu(
            text: "diffusion model",
            locator: #"{"href":"chapter-2.xhtml"}"#,
            chapter: "Chapter 2"
        )

        coordinator.handleAction(.search)

        #expect(coordinator.isMenuVisible == false)
        #expect(coordinator.selectedText.isEmpty)
        #expect(coordinator.pendingSearchQuery == "diffusion model")
    }

    @Test("takePendingSearchQuery returns the query once and clears it")
    func takePendingSearchQueryClearsPendingState() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "Search Once", database: database)
        let coordinator = ContextMenuCoordinator(
            bookId: bookID,
            bookTitle: "Search Once",
            bookAuthor: "PaperTok",
            database: database
        )

        coordinator.showMenu(
            text: "context window",
            locator: #"{"href":"chapter-3.xhtml"}"#,
            chapter: "Chapter 3"
        )
        coordinator.handleAction(.search)

        #expect(coordinator.takePendingSearchQuery() == "context window")
        #expect(coordinator.takePendingSearchQuery() == nil)
        #expect(coordinator.pendingSearchQuery == nil)
    }

    @Test("translation service provider resolves lazily for the current AI runtime")
    func translationServiceProviderResolvesLatestService() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "Translate Me", database: database)
        var currentService: AITranslationService?
        let coordinator = ContextMenuCoordinator(
            bookId: bookID,
            bookTitle: "Translate Me",
            bookAuthor: "PaperTok",
            database: database,
            translationServiceProvider: { currentService }
        )

        #expect(coordinator.translationService == nil)

        currentService = AITranslationService(
            provider: StaticTranslationProvider(),
            model: "translation-model"
        )

        coordinator.showMenu(
            text: "bonjour",
            locator: #"{"href":"chapter-4.xhtml"}"#,
            chapter: "Chapter 4"
        )
        coordinator.handleAction(.translate)

        #expect(coordinator.translationService != nil)
        #expect(coordinator.activeSheet == .translation)
        #expect(coordinator.isMenuVisible == false)
    }

    private func insertBook(title: String, database: AppDatabase) async throws -> Int64 {
        let bookDAO = BookDAO(database: database)
        let saved = try await bookDAO.save(Book.placeholder(title: title, filePath: "/\(UUID().uuidString).epub"))
        return try #require(saved.id)
    }
}
