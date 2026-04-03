import Testing
import GRDB
@testable import PTCore

@Suite("BookDAO Tests")
struct BookDAOTests {

    private func makeDAO() throws -> BookDAO {
        let db = try AppDatabase.makeInMemory()
        return BookDAO(database: db)
    }

    @Test("Insert and fetch by id")
    func insertAndFetch() async throws {
        let dao = try makeDAO()
        let book = Book.placeholder(title: "My Book", filePath: "/book.epub")
        let saved = try await dao.save(book)
        #expect(saved.id != nil)

        let fetched = try await dao.fetchById(saved.id!)
        #expect(fetched != nil)
        #expect(fetched?.title == "My Book")
    }

    @Test("fetchAll filters deleted books")
    func fetchAllFiltersDeleted() async throws {
        let dao = try makeDAO()
        _ = try await dao.save(Book.placeholder(title: "Visible", filePath: "/a.epub"))
        var deleted = Book.placeholder(title: "Deleted", filePath: "/b.epub")
        deleted.isDeleted = true
        _ = try await dao.save(deleted)

        let all = try await dao.fetchAll()
        #expect(all.count == 1)
        #expect(all[0].title == "Visible")
    }

    @Test("Update reading percentage")
    func updatePercentage() async throws {
        let dao = try makeDAO()
        var saved = try await dao.save(Book.placeholder(title: "Book", filePath: "/c.epub"))
        #expect(saved.readingPercentage == 0)

        saved.readingPercentage = 0.75
        let updated = try await dao.save(saved)
        #expect(updated.readingPercentage == 0.75)

        let fetched = try await dao.fetchById(updated.id!)
        #expect(fetched?.readingPercentage == 0.75)
    }

    @Test("Search by title")
    func searchByTitle() async throws {
        let dao = try makeDAO()
        _ = try await dao.save(Book.placeholder(title: "Swift Programming", filePath: "/d.epub"))
        _ = try await dao.save(Book.placeholder(title: "Kotlin Guide", filePath: "/e.epub"))

        let results = try await dao.search(query: "Swift")
        #expect(results.count == 1)
        #expect(results[0].title == "Swift Programming")
    }

    @Test("Soft delete sets is_deleted")
    func softDelete() async throws {
        let dao = try makeDAO()
        let saved = try await dao.save(Book.placeholder(title: "ToDelete", filePath: "/f.epub"))
        try await dao.softDelete(id: saved.id!)

        let fetched = try await dao.fetchById(saved.id!)
        #expect(fetched?.isDeleted == true)

        let all = try await dao.fetchAll()
        #expect(all.isEmpty)
    }
}
