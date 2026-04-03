import Foundation
import Testing
import GRDB
@testable import PTCore

@Suite("BookNoteDAO Tests")
struct BookNoteDAOTests {

    private func makeDAO() throws -> BookNoteDAO {
        let db = try AppDatabase.makeInMemory()
        return BookNoteDAO(database: db)
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
        let dao = try makeDAO()
        let saved = try await dao.save(makeNote(bookId: 1))
        #expect(saved.id != nil)

        let notes = try await dao.fetchByBookId(1)
        #expect(notes.count == 1)
        #expect(notes[0].content == "Some content")
    }

    @Test("Delete by id")
    func deleteById() async throws {
        let dao = try makeDAO()
        let saved = try await dao.save(makeNote(bookId: 1))
        try await dao.delete(id: saved.id!)

        let notes = try await dao.fetchByBookId(1)
        #expect(notes.isEmpty)
    }

    @Test("Count notes and books with notes")
    func countNotesAndBooks() async throws {
        let dao = try makeDAO()
        _ = try await dao.save(makeNote(bookId: 1))
        _ = try await dao.save(makeNote(bookId: 1))
        _ = try await dao.save(makeNote(bookId: 2))

        let (totalNotes, booksWithNotes) = try await dao.countNotesAndBooks()
        #expect(totalNotes == 3)
        #expect(booksWithNotes == 2)
    }

    @Test("Search by keyword")
    func searchByKeyword() async throws {
        let dao = try makeDAO()
        _ = try await dao.save(makeNote(bookId: 1, content: "Swift is great"))
        _ = try await dao.save(makeNote(bookId: 1, content: "Kotlin is nice"))

        let results = try await dao.search(keyword: "Swift")
        #expect(results.count == 1)
        #expect(results[0].content == "Swift is great")
    }
}
