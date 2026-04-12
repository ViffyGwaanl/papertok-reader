import Foundation
import Testing
@testable import PTFeatures
import PTReader

#if canImport(PDFKit)
import PDFKit

@Suite("PDFReaderAnnotationsViewModel")
@MainActor
struct PDFReaderAnnotationsViewModelTests {
    @Test("createAnnotation persists a PDF note and refreshes rendered annotations")
    func createAnnotationPersistsPDFNote() async throws {
        let database = try AppDatabase.makeInMemory()
        let noteDAO = BookNoteDAO(database: database)
        let bookID = try await insertBook(title: "PDF Notes", database: database)
        let document = makeDocument(pageCount: 1)
        let viewModel = PDFReaderAnnotationsViewModel(bookId: bookID, database: database, document: document)
        let anchor = PDFAnnotationAnchor(
            kind: .selection,
            pageIndex: 0,
            pageLabel: "Page 1",
            rects: [
                .init(pageIndex: 0, normalizedX: 0.1, normalizedY: 0.2, normalizedWidth: 0.3, normalizedHeight: 0.05)
            ]
        )

        let saved = await viewModel.createAnnotation(
            selectedText: "Important paragraph",
            locatorString: PDFAnnotationBridge.storedString(from: anchor),
            chapterTitle: "Page 1",
            type: .note,
            color: .blue,
            readerNote: "Remember this proof."
        )

        let persisted = try await noteDAO.fetchByBookId(bookID)
        let note = try #require(saved)
        #expect(note.id != nil)
        #expect(persisted.count == 1)
        #expect(persisted[0].type == NoteType.note.rawValue)
        #expect(persisted[0].content == "Important paragraph")
        #expect(persisted[0].readerNote == "Remember this proof.")
        #expect(viewModel.notes.count == 1)
        #expect(viewModel.renderedAnnotations.count == 1)
        #expect(viewModel.renderedAnnotations[0].pageIndex == 0)
        #expect(viewModel.renderedAnnotations[0].type == .note)
    }

    @Test("bookmark creation persists the page anchor and renders a bookmark marker")
    func bookmarkCreationRendersBookmarkMarker() async throws {
        let database = try AppDatabase.makeInMemory()
        let noteDAO = BookNoteDAO(database: database)
        let bookID = try await insertBook(title: "PDF Bookmark", database: database)
        let document = makeDocument(pageCount: 3)
        let viewModel = PDFReaderAnnotationsViewModel(bookId: bookID, database: database, document: document)

        _ = await viewModel.createAnnotation(
            selectedText: "",
            locatorString: PDFAnnotationBridge.storedString(from: .bookmark(pageIndex: 2, pageLabel: "Page 3")),
            chapterTitle: "Page 3",
            type: .bookmark,
            color: .red,
            readerNote: nil
        )

        let persisted = try await noteDAO.fetchByBookId(bookID)
        #expect(persisted.count == 1)
        #expect(persisted[0].type == NoteType.bookmark.rawValue)
        #expect(persisted[0].content == "Page 3")
        #expect(viewModel.renderedAnnotations.count == 1)
        #expect(viewModel.renderedAnnotations[0].pageIndex == 2)
        #expect(viewModel.renderedAnnotations[0].type == .bookmark)
    }

    @Test("annotationDraft returns an editable draft for an existing PDF note")
    func annotationDraftReturnsExistingNote() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "PDF Edit", database: database)
        let document = makeDocument(pageCount: 1)
        let viewModel = PDFReaderAnnotationsViewModel(bookId: bookID, database: database, document: document)
        let anchor = PDFAnnotationAnchor(
            kind: .selection,
            pageIndex: 0,
            pageLabel: "Page 1",
            rects: [
                .init(pageIndex: 0, normalizedX: 0.2, normalizedY: 0.3, normalizedWidth: 0.15, normalizedHeight: 0.08)
            ]
        )

        let saved = try #require(await viewModel.createAnnotation(
            selectedText: "Existing highlight",
            locatorString: PDFAnnotationBridge.storedString(from: anchor),
            chapterTitle: "Page 1",
            type: .note,
            color: .purple,
            readerNote: "Edit me."
        ))
        let noteID = try #require(saved.id)

        let draft = try #require(viewModel.annotationDraft(noteID: noteID))
        #expect(draft.noteID == noteID)
        #expect(draft.locatorString == saved.cfi)
        #expect(draft.selectedText == "Existing highlight")
        #expect(draft.chapterTitle == "Page 1")
        #expect(draft.type == .note)
        #expect(draft.color == .purple)
        #expect(draft.readerNote == "Edit me.")
    }

    @Test("annotationDraft returns nil for unknown PDF note ids")
    func annotationDraftReturnsNilForUnknownNoteID() throws {
        let database = try AppDatabase.makeInMemory()
        let document = makeDocument(pageCount: 1)
        let viewModel = PDFReaderAnnotationsViewModel(bookId: 1, database: database, document: document)

        #expect(viewModel.annotationDraft(noteID: 999) == nil)
    }

    private func insertBook(title: String, database: AppDatabase) async throws -> Int64 {
        let bookDAO = BookDAO(database: database)
        let saved = try await bookDAO.save(Book.placeholder(title: title, filePath: "/\(UUID().uuidString).pdf"))
        return try #require(saved.id)
    }

    private func makeDocument(pageCount: Int) -> PDFDocument {
        let document = PDFDocument()
        for index in 0..<pageCount {
            document.insert(PDFPage(), at: index)
        }
        return document
    }
}
#endif
