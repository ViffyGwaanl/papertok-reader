import Foundation
import Testing
import GRDB
@testable import PTCore

@Suite("BookNoteDAO Tests")
struct BookNoteDAOTests {

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.makeInMemory()
    }

    /// Insert a parent book so FK constraints are satisfied.
    private func insertBook(id: Int64, database: AppDatabase) async throws {
        let dao = BookDAO(database: database)
        var book = Book.placeholder(title: "Book \(id)", filePath: "/book\(id).pdf")
        book.id = id
        _ = try await dao.save(book)
    }

    private func makeNote(bookId: Int64, content: String = "Some content", chapter: String = "Chapter 1") -> BookNote {
        BookNote(
            id: nil,
            bookId: bookId,
            content: content,
            cfi: "epubcfi(/6/4)",
            chapter: chapter,
            type: "highlight",
            color: "#FFFF00",
            readerNote: nil,
            createTime: Date(),
            updateTime: Date()
        )
    }

    @Test("Insert and fetch by book id")
    func insertAndFetchByBook() async throws {
        let db = try makeDB()
        try await insertBook(id: 1, database: db)
        let dao = BookNoteDAO(database: db)
        let saved = try await dao.save(makeNote(bookId: 1))
        #expect(saved.id != nil)

        let notes = try await dao.fetchByBookId(1)
        #expect(notes.count == 1)
        #expect(notes[0].content == "Some content")
    }

    @Test("Delete by id")
    func deleteById() async throws {
        let db = try makeDB()
        try await insertBook(id: 1, database: db)
        let dao = BookNoteDAO(database: db)
        let saved = try await dao.save(makeNote(bookId: 1))
        try await dao.delete(id: saved.id!)

        let notes = try await dao.fetchByBookId(1)
        #expect(notes.isEmpty)
    }

    @Test("Count notes and books with notes")
    func countNotesAndBooks() async throws {
        let db = try makeDB()
        try await insertBook(id: 1, database: db)
        try await insertBook(id: 2, database: db)
        let dao = BookNoteDAO(database: db)
        _ = try await dao.save(makeNote(bookId: 1))
        _ = try await dao.save(makeNote(bookId: 1))
        _ = try await dao.save(makeNote(bookId: 2))

        let (totalNotes, booksWithNotes) = try await dao.countNotesAndBooks()
        #expect(totalNotes == 3)
        #expect(booksWithNotes == 2)
    }

    @Test("Search by keyword")
    func searchByKeyword() async throws {
        let db = try makeDB()
        try await insertBook(id: 1, database: db)
        let dao = BookNoteDAO(database: db)
        _ = try await dao.save(makeNote(bookId: 1, content: "Swift is great"))
        _ = try await dao.save(makeNote(bookId: 1, content: "Kotlin is nice"))

        let results = try await dao.search(keyword: "Swift")
        #expect(results.count == 1)
        #expect(results[0].content == "Swift is great")
    }
}
