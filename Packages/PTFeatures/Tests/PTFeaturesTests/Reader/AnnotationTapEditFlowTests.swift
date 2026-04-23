import Foundation
import Testing
@testable import PTFeatures
import PTCore
import PTReader

#if canImport(PDFKit)
import PDFKit
#endif

/// Verifies the W6.5 "tap an existing annotation to edit it" wiring:
/// annotation taps route through the reader annotations view-models into the
/// shared `ContextMenuCoordinator`, which in turn activates the
/// `.noteEdit(noteID:)` sheet. The sheet body is driven by coordinator state
/// (selectedText, chapterTitle, highlightColor, annotationKind), so we assert
/// those fields are hydrated with the tapped annotation's values.
@Suite("AnnotationTapEditFlow")
@MainActor
struct AnnotationTapEditFlowTests {

    // MARK: Helpers

    private func insertBook(title: String, database: AppDatabase) async throws -> Int64 {
        let bookDAO = BookDAO(database: database)
        let saved = try await bookDAO.save(Book.placeholder(title: title, filePath: "/\(UUID().uuidString).epub"))
        return try #require(saved.id)
    }

    private func makeCoordinator(bookID: Int64, database: AppDatabase) -> ContextMenuCoordinator {
        ContextMenuCoordinator(
            bookId: bookID,
            bookTitle: "Tap Edit Book",
            bookAuthor: "PaperTok",
            database: database
        )
    }

    private func seedHighlight(
        bookID: Int64,
        database: AppDatabase,
        type: NoteType = .highlight,
        color: HighlightColor = .yellow,
        content: String = "Tapped passage",
        chapter: String = "Chapter 7",
        locator: String = #"{"href":"chapter-7.xhtml"}"#
    ) async throws -> BookNote {
        let noteDAO = BookNoteDAO(database: database)
        return try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: content,
                cfi: locator,
                chapter: chapter,
                type: type.rawValue,
                color: color.hex,
                readerNote: nil,
                createTime: Date(),
                updateTime: Date()
            )
        )
    }

    // MARK: A1 — tapping a highlight opens the edit sheet

    @Test("tapping highlight opens edit sheet via coordinator")
    func tappingHighlightOpensEditSheet() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "Tap Flow EPUB", database: database)
        let original = try await seedHighlight(bookID: bookID, database: database)
        let noteID = try #require(original.id)

        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
        await viewModel.loadAnnotations()

        let coordinator = makeCoordinator(bookID: bookID, database: database)
        #expect(coordinator.activeSheet == nil)

        let routed = viewModel.handleAnnotationTap(id: noteID, coordinator: coordinator)

        #expect(routed == true)
        #expect(coordinator.activeSheet == .noteEdit(noteID: noteID))
        #expect(coordinator.isMenuVisible == false)
    }

    // MARK: A2 — sheet state is populated with current annotation data

    @Test("edit sheet state is populated with current annotation data")
    func editSheetPopulatedWithCurrentAnnotationData() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "Populate", database: database)
        let original = try await seedHighlight(
            bookID: bookID,
            database: database,
            type: .underline,
            color: .green,
            content: "Distinct phrase",
            chapter: "Chapter 3",
            locator: #"{"href":"chapter-3.xhtml"}"#
        )
        let noteID = try #require(original.id)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
        await viewModel.loadAnnotations()
        let coordinator = makeCoordinator(bookID: bookID, database: database)

        _ = viewModel.handleAnnotationTap(id: noteID, coordinator: coordinator)

        #expect(coordinator.selectedText == "Distinct phrase")
        #expect(coordinator.chapterTitle == "Chapter 3")
        #expect(coordinator.selectedLocator == #"{"href":"chapter-3.xhtml"}"#)
        #expect(coordinator.highlightColor == .green)
        #expect(coordinator.annotationKind == .underline)
    }

    // MARK: A3 — deleting from the edit sheet removes the annotation

    @Test("deleting from the edit sheet removes the annotation")
    func deletingFromEditSheetRemovesAnnotation() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "Delete Flow", database: database)
        let original = try await seedHighlight(bookID: bookID, database: database)
        let noteID = try #require(original.id)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
        await viewModel.loadAnnotations()
        let coordinator = makeCoordinator(bookID: bookID, database: database)

        _ = viewModel.handleAnnotationTap(id: noteID, coordinator: coordinator)
        await coordinator.deleteNote(id: noteID)

        let noteDAO = BookNoteDAO(database: database)
        let persisted = try await noteDAO.fetchByBookId(bookID)
        #expect(persisted.isEmpty)
        #expect(coordinator.activeSheet == nil)
    }

    // MARK: A4 — changing kind via the VM updates the stored annotation

    @Test("changing kind from the edit sheet updates the stored annotation")
    func changingKindFromEditSheetUpdatesAnnotation() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "Change Kind", database: database)
        let original = try await seedHighlight(bookID: bookID, database: database, type: .highlight)
        let noteID = try #require(original.id)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
        await viewModel.loadAnnotations()
        let coordinator = makeCoordinator(bookID: bookID, database: database)

        _ = viewModel.handleAnnotationTap(id: noteID, coordinator: coordinator)
        #expect(coordinator.annotationKind == .highlight)

        let updated = await viewModel.updateAnnotation(
            id: noteID,
            type: .strikethrough,
            color: .yellow,
            readerNote: nil
        )

        let saved = try #require(updated)
        #expect(saved.type == NoteType.strikethrough.rawValue)
        let persisted = try await BookNoteDAO(database: database).fetchByBookId(bookID)
        #expect(persisted.first?.type == NoteType.strikethrough.rawValue)
    }

    // MARK: A5 — unknown ids are ignored without mutating coordinator state

    @Test("tapping an unknown annotation id leaves the coordinator idle")
    func tappingUnknownAnnotationIsNoop() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "Unknown Tap", database: database)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
        await viewModel.loadAnnotations()
        let coordinator = makeCoordinator(bookID: bookID, database: database)

        let routed = viewModel.handleAnnotationTap(id: 999_999, coordinator: coordinator)

        #expect(routed == false)
        #expect(coordinator.activeSheet == nil)
        #expect(coordinator.selectedText.isEmpty)
    }

    // MARK: PDF — parity with the EPUB tap flow

    #if canImport(PDFKit)
    @Test("PDF tap routes through the same coordinator edit sheet")
    func pdfAnnotationTapOpensEditSheet() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "PDF Tap", database: database)
        let noteDAO = BookNoteDAO(database: database)
        let anchor = PDFAnnotationAnchor(
            kind: .selection,
            pageIndex: 0,
            pageLabel: "1",
            rects: [
                PDFAnnotationAnchor.Rect(
                    pageIndex: 0,
                    normalizedX: 0.1,
                    normalizedY: 0.1,
                    normalizedWidth: 0.2,
                    normalizedHeight: 0.05
                )
            ]
        )
        let original = try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: "PDF selection",
                cfi: PDFAnnotationBridge.storedString(from: anchor),
                chapter: "Page 1",
                type: NoteType.highlight.rawValue,
                color: HighlightColor.red.hex,
                readerNote: nil,
                createTime: Date(),
                updateTime: Date()
            )
        )
        let noteID = try #require(original.id)
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let viewModel = PDFReaderAnnotationsViewModel(
            bookId: bookID,
            database: database,
            document: document
        )
        await viewModel.loadAnnotations()
        let coordinator = makeCoordinator(bookID: bookID, database: database)

        let routed = viewModel.handleAnnotationTap(id: noteID, coordinator: coordinator)

        #expect(routed == true)
        #expect(coordinator.activeSheet == .noteEdit(noteID: noteID))
        #expect(coordinator.selectedText == "PDF selection")
        #expect(coordinator.highlightColor == .red)
    }
    #endif
}
