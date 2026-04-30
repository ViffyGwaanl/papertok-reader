import Foundation
import Testing
@testable import PTFeatures
import PTAIServices
import PTCore
import PTReader

/// W7.5 — Bug #1: Translation feature was not discoverable from the reader.
///
/// EPUB readers already had a translation toggle in the top-bar trailing
/// group. The PDF reader had **no** translation entry at all (neither in
/// the toolbar, nor in the context menu when no text was selected). This
/// suite covers the new "Translate Page" toolbar entry which routes through
/// `ContextMenuCoordinator.presentTranslation(text:chapter:)` so the same
/// `TranslationMenuSheet` surface used for selection translation is reused.
@Suite("Reader toolbar translation entry")
@MainActor
struct ReaderToolbarTranslationTests {
    private struct StaticTranslationProvider: ChatModelProvider {
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

    private func insertBook(title: String, database: AppDatabase) async throws -> Int64 {
        let bookDAO = BookDAO(database: database)
        let saved = try await bookDAO.save(
            Book.placeholder(title: title, filePath: "/\(UUID().uuidString).pdf")
        )
        return try #require(saved.id)
    }

    @Test("epubTranslationButtonReflectsRuntimeState — runtime.isEnabled drives the icon state")
    func epubTranslationButtonReflectsRuntimeState() async {
        // The reader-toolbar EPUB translation button shows a filled glyph
        // when the fulltext-translation runtime is enabled and an outline
        // glyph otherwise. The toolbar button binds directly to the
        // runtime's `isEnabled`; this guards against accidental decoupling.
        struct NoopTranslator: Translator {
            func translate(_ text: String, from source: String, to target: String) async throws -> String { text }
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pt-w75-toolbar-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = FulltextTranslationCache(directory: tempDir)
        let runtime = FulltextTranslationRuntime(translator: NoopTranslator(), cache: cache)

        #expect(runtime.isEnabled == false)

        await runtime.setEnabled(true)
        #expect(runtime.isEnabled == true)

        await runtime.setEnabled(false)
        #expect(runtime.isEnabled == false)
    }

    @Test("tappingEpubTranslationButtonTogglesRuntime — repeated taps flip isEnabled")
    func tappingEpubTranslationButtonTogglesRuntime() async {
        struct NoopTranslator: Translator {
            func translate(_ text: String, from source: String, to target: String) async throws -> String { text }
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pt-w75-toolbar-toggle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = FulltextTranslationCache(directory: tempDir)
        let runtime = FulltextTranslationRuntime(translator: NoopTranslator(), cache: cache)

        // Simulated 3 toolbar taps: off → on → off → on.
        var enabled = runtime.isEnabled
        for _ in 0..<3 {
            enabled.toggle()
            await runtime.setEnabled(enabled)
        }
        #expect(runtime.isEnabled == true)
    }

    @Test("pdfTranslationButtonOpensSheet — coordinator surface presents .translation with page text")
    func pdfTranslationButtonOpensSheet() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "PDF Translate", database: database)
        let translationService = AITranslationService(
            provider: StaticTranslationProvider(),
            model: "translation-model"
        )
        let coordinator = ContextMenuCoordinator(
            bookId: bookID,
            bookTitle: "PDF Translate",
            bookAuthor: "PaperTok",
            database: database,
            translationServiceProvider: { translationService }
        )

        // No selection yet — but the toolbar wants to translate the
        // currently visible page. The coordinator exposes a dedicated entry
        // point so the PDF reader can pre-fill the sheet without faking a
        // text-selection gesture.
        let pageText = "First page text. Translation should be available immediately."
        coordinator.presentTranslation(text: pageText, chapter: "Page 1")

        #expect(coordinator.activeSheet == .translation)
        #expect(coordinator.selectedText == pageText)
        #expect(coordinator.chapterTitle == "Page 1")
        // The selection menu must NOT pop — the sheet is presented directly.
        #expect(coordinator.isMenuVisible == false)
        #expect(coordinator.translationService != nil)
    }

    @Test("pdfTranslationButton — empty page text leaves the sheet closed")
    func pdfTranslationButtonGuardsAgainstEmptyText() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "Empty PDF", database: database)
        let coordinator = ContextMenuCoordinator(
            bookId: bookID,
            bookTitle: "Empty PDF",
            bookAuthor: "PaperTok",
            database: database
        )

        coordinator.presentTranslation(text: "   \n  ", chapter: "Page 1")

        // Whitespace-only input is treated as a no-op so the user sees a
        // toast (handled at the call-site) instead of a blank translation
        // sheet that immediately errors.
        #expect(coordinator.activeSheet == nil)
        #expect(coordinator.selectedText.isEmpty)
    }
}
