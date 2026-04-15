import Foundation
import Testing
@testable import PTFeatures
import PTCore
import PTReader

#if canImport(PDFKit)
import PDFKit
#endif

/// Covers the in-place annotation kind-editor flow surfaced by
/// `EPUBReaderAnnotationEditorView`. For every transition in the
/// (highlight | underline | strikethrough) x (highlight | underline |
/// strikethrough) matrix, calling `updateAnnotation(id:type:color:readerNote:)`
/// on the view-model must land the persisted note in the requested type while
/// keeping the original color and locator.
@Suite("AnnotationEditFlow")
@MainActor
struct AnnotationEditFlowTests {

    private static let kinds: [NoteType] = [.highlight, .underline, .strikethrough]

    // MARK: EPUB

    @Test("EPUB VM: every 3x3 kind transition persists the target type", arguments: kinds)
    func epubAllTransitions(from startKind: NoteType) async throws {
        for targetKind in Self.kinds {
            let database = try AppDatabase.makeInMemory()
            let bookID = try await insertBook(title: "Edit Flow", database: database)
            let noteDAO = BookNoteDAO(database: database)
            let original = try await noteDAO.save(
                BookNote(
                    bookId: bookID,
                    content: "Transition source",
                    cfi: #"{"href":"chapter-1.xhtml","title":"Chapter 1"}"#,
                    chapter: "Chapter 1",
                    type: startKind.rawValue,
                    color: HighlightColor.yellow.hex,
                    readerNote: nil,
                    createTime: Date(),
                    updateTime: Date()
                )
            )
            let noteID = try #require(original.id)
            let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
            await viewModel.loadAnnotations()

            let updated = await viewModel.updateAnnotation(
                id: noteID,
                type: targetKind,
                color: .yellow,
                readerNote: nil
            )

            let saved = try #require(updated)
            #expect(saved.type == targetKind.rawValue)
            #expect(saved.color == HighlightColor.yellow.hex)
            let persisted = try await noteDAO.fetchByBookId(bookID)
            #expect(persisted.count == 1)
            #expect(persisted[0].type == targetKind.rawValue)
            #expect(persisted[0].cfi == #"{"href":"chapter-1.xhtml","title":"Chapter 1"}"#)
            #expect(persisted[0].content == "Transition source")
        }
    }

    // MARK: PDF

    #if canImport(PDFKit)
    @Test("PDF VM: every 3x3 kind transition persists the target type", arguments: kinds)
    func pdfAllTransitions(from startKind: NoteType) async throws {
        let document = Self.makePDFDocument()
        for targetKind in Self.kinds {
            let database = try AppDatabase.makeInMemory()
            let bookID = try await insertBook(title: "Edit Flow PDF", database: database)
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
                    content: "pdf source",
                    cfi: PDFAnnotationBridge.storedString(from: anchor),
                    chapter: "Page 1",
                    type: startKind.rawValue,
                    color: HighlightColor.yellow.hex,
                    readerNote: nil,
                    createTime: Date(),
                    updateTime: Date()
                )
            )
            let noteID = try #require(original.id)
            let viewModel = PDFReaderAnnotationsViewModel(
                bookId: bookID,
                database: database,
                document: document
            )
            await viewModel.loadAnnotations()

            let updated = await viewModel.updateAnnotation(
                id: noteID,
                type: targetKind,
                color: .yellow,
                readerNote: nil
            )

            let saved = try #require(updated)
            #expect(saved.type == targetKind.rawValue)
            #expect(saved.color == HighlightColor.yellow.hex)
            let persisted = try await noteDAO.fetchByBookId(bookID)
            #expect(persisted.count == 1)
            #expect(persisted[0].type == targetKind.rawValue)
            #expect(persisted[0].content == "pdf source")
        }
    }

    private static func makePDFDocument() -> PDFDocument {
        let page = PDFPage()
        let document = PDFDocument()
        document.insert(page, at: 0)
        return document
    }
    #endif

    @Test("EPUB VM: changing color while keeping kind updates just the color")
    func epubColorOnlyChange() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "Color Only", database: database)
        let noteDAO = BookNoteDAO(database: database)
        let original = try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: "Selection",
                cfi: #"{"href":"c.xhtml"}"#,
                chapter: "c",
                type: NoteType.underline.rawValue,
                color: HighlightColor.yellow.hex,
                readerNote: nil,
                createTime: Date(),
                updateTime: Date()
            )
        )
        let noteID = try #require(original.id)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
        await viewModel.loadAnnotations()

        let updated = await viewModel.updateAnnotation(
            id: noteID,
            type: .underline,
            color: .green,
            readerNote: nil
        )

        let saved = try #require(updated)
        #expect(saved.type == NoteType.underline.rawValue)
        #expect(saved.color == HighlightColor.green.hex)
    }

    private func insertBook(title: String, database: AppDatabase) async throws -> Int64 {
        let bookDAO = BookDAO(database: database)
        let saved = try await bookDAO.save(Book.placeholder(title: title, filePath: "/\(UUID().uuidString).epub"))
        return try #require(saved.id)
    }
}
