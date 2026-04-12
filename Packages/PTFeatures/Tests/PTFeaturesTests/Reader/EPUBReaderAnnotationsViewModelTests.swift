import Foundation
import Testing
@testable import PTFeatures
import PTReader

@Suite("EPUBReaderAnnotationsViewModel")
@MainActor
struct EPUBReaderAnnotationsViewModelTests {
    @Test("loadAnnotations loads persisted notes for the active book")
    func loadAnnotationsLoadsPersistedNotes() async throws {
        let database = try AppDatabase.makeInMemory()
        let noteDAO = BookNoteDAO(database: database)
        let bookID = try await insertBook(title: "EPUB Notes", database: database)

        _ = try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: "First highlight",
                cfi: #"{"href":"chapter-1.xhtml"}"#,
                chapter: "Chapter 1",
                type: NoteType.highlight.rawValue,
                color: HighlightColor.yellow.hex,
                readerNote: nil,
                createTime: makeDate("2026-04-07"),
                updateTime: makeDate("2026-04-07")
            )
        )
        _ = try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: "Second note",
                cfi: #"{"href":"chapter-2.xhtml"}"#,
                chapter: "Chapter 2",
                type: NoteType.note.rawValue,
                color: HighlightColor.purple.hex,
                readerNote: "Follow up on this section.",
                createTime: makeDate("2026-04-08"),
                updateTime: makeDate("2026-04-08")
            )
        )

        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)

        await viewModel.loadAnnotations()

        #expect(viewModel.notes.count == 2)
        #expect(viewModel.notes.map(\.content) == ["Second note", "First highlight"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test("createAnnotation persists a highlight and refreshes the in-memory notes")
    func createAnnotationPersistsHighlight() async throws {
        let database = try AppDatabase.makeInMemory()
        let noteDAO = BookNoteDAO(database: database)
        let bookID = try await insertBook(title: "Highlight Book", database: database)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)

        let saved = await viewModel.createAnnotation(
            selectedText: "Important result",
            locatorString: #"{"href":"chapter-3.xhtml","title":"Chapter 3"}"#,
            chapterTitle: "Chapter 3",
            type: .highlight,
            color: .green,
            readerNote: nil
        )

        let persisted = try await noteDAO.fetchByBookId(bookID)
        let note = try #require(saved)
        #expect(note.id != nil)
        #expect(persisted.count == 1)
        #expect(persisted[0].content == "Important result")
        #expect(persisted[0].type == NoteType.highlight.rawValue)
        #expect(persisted[0].color == HighlightColor.green.hex)
        #expect(viewModel.notes.count == 1)
        #expect(viewModel.notes[0].content == "Important result")
    }

    @Test("createAnnotation persists markdown reader notes for note annotations")
    func createAnnotationPersistsReaderNote() async throws {
        let database = try AppDatabase.makeInMemory()
        let noteDAO = BookNoteDAO(database: database)
        let bookID = try await insertBook(title: "Markdown Notes", database: database)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)

        _ = await viewModel.createAnnotation(
            selectedText: "A theorem worth reviewing",
            locatorString: #"{"href":"chapter-4.xhtml","title":"Chapter 4"}"#,
            chapterTitle: "Chapter 4",
            type: .note,
            color: .blue,
            readerNote: "## Review\n\n- revisit proof\n- compare with appendix"
        )

        let persisted = try await noteDAO.fetchByBookId(bookID)
        #expect(persisted.count == 1)
        #expect(persisted[0].type == NoteType.note.rawValue)
        #expect(persisted[0].color == HighlightColor.blue.hex)
        #expect(persisted[0].readerNote?.contains("revisit proof") == true)
    }

    @Test("bookmark creation falls back to chapter title when no text is selected")
    func createBookmarkUsesChapterTitleFallback() async throws {
        let database = try AppDatabase.makeInMemory()
        let noteDAO = BookNoteDAO(database: database)
        let bookID = try await insertBook(title: "Bookmark Notes", database: database)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)

        _ = await viewModel.createAnnotation(
            selectedText: "   ",
            locatorString: #"{"href":"chapter-4.xhtml","title":"Chapter 4"}"#,
            chapterTitle: "Chapter 4",
            type: .bookmark,
            color: .red,
            readerNote: nil
        )

        let persisted = try await noteDAO.fetchByBookId(bookID)
        #expect(persisted.count == 1)
        #expect(persisted[0].type == NoteType.bookmark.rawValue)
        #expect(persisted[0].content == "Chapter 4")
    }

    @Test("createAnnotation rejects empty-selection highlights and notes")
    func createAnnotationRejectsEmptySelectionForSelectionBackedTypes() async throws {
        let database = try AppDatabase.makeInMemory()
        let noteDAO = BookNoteDAO(database: database)
        let bookID = try await insertBook(title: "Invalid Selection Notes", database: database)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)

        let saved = await viewModel.createAnnotation(
            selectedText: "   ",
            locatorString: #"{"href":"chapter-4.xhtml","title":"Chapter 4"}"#,
            chapterTitle: "Chapter 4",
            type: .note,
            color: .blue,
            readerNote: "Should not persist"
        )

        let persisted = try await noteDAO.fetchByBookId(bookID)
        #expect(saved == nil)
        #expect(persisted.isEmpty)
        #expect(viewModel.errorMessage == "Highlights and notes require selected text.")
    }

    @Test("updateAnnotation changes type color and reader note while preserving selection fields")
    func updateAnnotationPreservesSelectionFields() async throws {
        let database = try AppDatabase.makeInMemory()
        let noteDAO = BookNoteDAO(database: database)
        let bookID = try await insertBook(title: "Editable Notes", database: database)
        let original = try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: "Original selection",
                cfi: #"{"href":"chapter-5.xhtml","title":"Chapter 5"}"#,
                chapter: "Chapter 5",
                type: NoteType.highlight.rawValue,
                color: HighlightColor.yellow.hex,
                readerNote: nil,
                createTime: makeDate("2026-04-07"),
                updateTime: makeDate("2026-04-07")
            )
        )
        let noteID = try #require(original.id)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
        await viewModel.loadAnnotations()

        let updated = await viewModel.updateAnnotation(
            id: noteID,
            type: .note,
            color: .purple,
            readerNote: "**Action item:** summarize this chapter."
        )

        let persisted = try await noteDAO.fetchByBookId(bookID)
        let saved = try #require(updated)
        #expect(saved.id == noteID)
        #expect(persisted.count == 1)
        #expect(persisted[0].content == "Original selection")
        #expect(persisted[0].chapter == "Chapter 5")
        #expect(persisted[0].cfi == #"{"href":"chapter-5.xhtml","title":"Chapter 5"}"#)
        #expect(persisted[0].type == NoteType.note.rawValue)
        #expect(persisted[0].color == HighlightColor.purple.hex)
        #expect(persisted[0].readerNote?.contains("Action item") == true)
    }

    @Test("updateAnnotation rejects converting bookmarks into selection-backed annotations")
    func updateAnnotationRejectsBookmarkTypeSwitchWithoutSelection() async throws {
        let database = try AppDatabase.makeInMemory()
        let noteDAO = BookNoteDAO(database: database)
        let bookID = try await insertBook(title: "Bookmark Conversion", database: database)
        let original = try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: "Chapter 7",
                cfi: #"{"href":"chapter-7.xhtml","title":"Chapter 7"}"#,
                chapter: "Chapter 7",
                type: NoteType.bookmark.rawValue,
                color: HighlightColor.yellow.hex,
                readerNote: nil,
                createTime: makeDate("2026-04-08"),
                updateTime: makeDate("2026-04-08")
            )
        )
        let noteID = try #require(original.id)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
        await viewModel.loadAnnotations()

        let updated = await viewModel.updateAnnotation(
            id: noteID,
            type: .note,
            color: .purple,
            readerNote: "Should not save"
        )

        let persisted = try await noteDAO.fetchByBookId(bookID)
        #expect(updated == nil)
        #expect(persisted.count == 1)
        #expect(persisted[0].type == NoteType.bookmark.rawValue)
        #expect(persisted[0].readerNote == nil)
        #expect(viewModel.errorMessage == "Highlights and notes require selected text.")
    }

    @Test("bookmark drafts do not treat chapter-title fallback text as a selected excerpt")
    func bookmarkDraftLeavesSelectedTextEmpty() {
        let bookmark = BookNote(
            id: 8,
            bookId: 5,
            content: "Chapter 8",
            cfi: #"{"href":"chapter-8.xhtml","title":"Chapter 8"}"#,
            chapter: "Chapter 8",
            type: NoteType.bookmark.rawValue,
            color: HighlightColor.red.hex,
            readerNote: nil,
            createTime: makeDate("2026-04-08"),
            updateTime: makeDate("2026-04-08")
        )

        let draft = EPUBReaderAnnotationDraft(note: bookmark)

        #expect(draft.type == .bookmark)
        #expect(draft.chapterTitle == "Chapter 8")
        #expect(draft.selectedText.isEmpty)
    }

    @Test("deleteAnnotation removes the note from persistence and in-memory state")
    func deleteAnnotationRemovesPersistedNote() async throws {
        let database = try AppDatabase.makeInMemory()
        let noteDAO = BookNoteDAO(database: database)
        let bookID = try await insertBook(title: "Delete Notes", database: database)
        let saved = try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: "Delete me",
                cfi: #"{"href":"chapter-6.xhtml"}"#,
                chapter: "Chapter 6",
                type: NoteType.bookmark.rawValue,
                color: HighlightColor.red.hex,
                readerNote: nil,
                createTime: makeDate("2026-04-08"),
                updateTime: makeDate("2026-04-08")
            )
        )
        let noteID = try #require(saved.id)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
        await viewModel.loadAnnotations()

        await viewModel.deleteAnnotation(id: noteID)

        let persisted = try await noteDAO.fetchByBookId(bookID)
        #expect(persisted.isEmpty)
        #expect(viewModel.notes.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    private func insertBook(title: String, database: AppDatabase) async throws -> Int64 {
        let bookDAO = BookDAO(database: database)
        let saved = try await bookDAO.save(Book.placeholder(title: title, filePath: "/\(UUID().uuidString).epub"))
        return try #require(saved.id)
    }

    private func makeDate(_ raw: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)!
    }
}
