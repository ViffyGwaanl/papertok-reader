import Foundation
import Testing
@testable import PTFeatures

@Suite("NotesViewModel")
@MainActor
struct NotesViewModelTests {
    @Test("loadNotes resolves book titles and summary")
    func loadNotesResolvesBookTitlesAndSummary() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let noteDAO = BookNoteDAO(database: database)

        let swiftBook = try await bookDAO.save(Book.placeholder(title: "Swift Notes", filePath: "/swift.epub"))
        let aiBook = try await bookDAO.save(Book.placeholder(title: "AI Research", filePath: "/ai.epub"))
        let swiftBookID = try #require(swiftBook.id)
        let aiBookID = try #require(aiBook.id)

        _ = try await noteDAO.save(
            BookNote(
                bookId: swiftBookID,
                content: "Remember protocol extensions",
                cfi: "epubcfi(/6/2)",
                chapter: "Chapter 1",
                type: "highlight",
                color: "#ffff00",
                readerNote: "Tie this to value semantics.",
                createTime: makeDate("2026-04-07"),
                updateTime: makeDate("2026-04-07")
            )
        )
        _ = try await noteDAO.save(
            BookNote(
                bookId: aiBookID,
                content: "Bookmark the evaluation section",
                cfi: "epubcfi(/6/4)",
                chapter: "Results",
                type: "bookmark",
                color: "purple",
                readerNote: nil,
                createTime: makeDate("2026-04-06"),
                updateTime: makeDate("2026-04-06")
            )
        )

        let viewModel = NotesViewModel(database: database)
        await viewModel.loadNotes()

        #expect(viewModel.groupedNotes.count == 2)
        #expect(viewModel.groupedNotes.map(\.bookTitle) == ["Swift Notes", "AI Research"])
        #expect(viewModel.summary.totalNotes == 2)
        #expect(viewModel.summary.booksWithNotes == 2)
    }

    @Test("export renders resolved book titles in markdown and csv")
    func exportRendersResolvedBookTitles() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let noteDAO = BookNoteDAO(database: database)

        let book = try await bookDAO.save(Book.placeholder(title: "Exported Book", filePath: "/export.epub"))
        let bookID = try #require(book.id)
        _ = try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: "Important paragraph",
                cfi: "epubcfi(/6/8)",
                chapter: "Conclusion",
                type: "note",
                color: "green",
                readerNote: "**Follow up** on this argument.",
                createTime: makeDate("2026-04-05"),
                updateTime: makeDate("2026-04-05")
            )
        )

        let viewModel = NotesViewModel(database: database)
        await viewModel.loadNotes()

        let markdown = viewModel.export(format: .markdown)
        #expect(markdown.contains("Exported Book"))
        #expect(markdown.contains("Important paragraph"))
        #expect(markdown.contains("Follow up"))

        let csv = viewModel.export(format: .csv)
        #expect(csv.contains("book_title,note_type"))
        #expect(csv.contains("Exported Book"))
        #expect(csv.contains("Important paragraph"))
    }

    @Test("note color normalization handles named and hex values")
    func noteColorNormalization() {
        #expect(NoteColorResolver.normalizedHex(for: "yellow") == "E8D890")
        #expect(NoteColorResolver.normalizedHex(for: "#ff00aa") == "FF00AA")
        #expect(NoteColorResolver.normalizedHex(for: "ffd700") == "FFD700")
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
