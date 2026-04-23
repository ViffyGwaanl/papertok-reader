import Foundation
import Testing
@testable import PTFeatures
import PTCore
import PTReader

@Suite("EPUB bookmark toolbar toggle")
@MainActor
struct BookmarkToggleTests {
    @Test("toggleCreatesBookmarkWhenNotPresent persists a bookmark note")
    func toggleCreatesBookmarkWhenNotPresent() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "EPUB Toggle Create", database: database)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
        await viewModel.loadAnnotations()

        let locatorString = #"{"href":"chapter-1.xhtml","locations":{"progression":0.1}}"#
        #expect(viewModel.isBookmarked(locatorString: locatorString) == false)

        await viewModel.toggleBookmark(
            locatorString: locatorString,
            chapterTitle: "Chapter 1"
        )

        #expect(viewModel.notes.count == 1)
        let note = try #require(viewModel.notes.first)
        #expect(note.type == NoteType.bookmark.rawValue)
        #expect(viewModel.isBookmarked(locatorString: locatorString))
    }

    @Test("toggleRemovesBookmarkWhenPresent deletes the matching note")
    func toggleRemovesBookmarkWhenPresent() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookID = try await insertBook(title: "EPUB Toggle Remove", database: database)
        let viewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
        await viewModel.loadAnnotations()

        let locatorString = #"{"href":"chapter-2.xhtml","locations":{"progression":0.2}}"#

        await viewModel.toggleBookmark(
            locatorString: locatorString,
            chapterTitle: "Chapter 2"
        )
        #expect(viewModel.notes.count == 1)
        #expect(viewModel.isBookmarked(locatorString: locatorString))

        await viewModel.toggleBookmark(
            locatorString: locatorString,
            chapterTitle: "Chapter 2"
        )

        #expect(viewModel.notes.isEmpty)
        #expect(viewModel.isBookmarked(locatorString: locatorString) == false)
    }

    @Test("iconReflectsState selects the filled or outline glyph")
    func iconReflectsState() {
        #expect(BookmarkToolbarIcon.systemName(isBookmarked: true) == "bookmark.fill")
        #expect(BookmarkToolbarIcon.systemName(isBookmarked: false) == "bookmark")
    }

    @Test("iconReflectsState chooses the correct a11y key")
    func iconReflectsAccessibilityLabel() {
        #expect(BookmarkToolbarIcon.accessibilityKey(isBookmarked: true) == "reader.toolbar.bookmark.remove")
        #expect(BookmarkToolbarIcon.accessibilityKey(isBookmarked: false) == "reader.toolbar.bookmark.add")
    }

    private func insertBook(title: String, database: AppDatabase) async throws -> Int64 {
        let bookDAO = BookDAO(database: database)
        let saved = try await bookDAO.save(Book.placeholder(title: title, filePath: "/\(UUID().uuidString).epub"))
        return try #require(saved.id)
    }
}
