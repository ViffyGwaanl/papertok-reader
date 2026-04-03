import Testing
import GRDB
@testable import PTCore

@Suite("ReadingTimeDAO Tests")
struct ReadingTimeDAOTests {

    private func makeDAO() throws -> ReadingTimeDAO {
        let db = try AppDatabase.makeInMemory()
        return ReadingTimeDAO(database: db)
    }

    @Test("Insert and total time for book")
    func insertAndTotalTime() async throws {
        let dao = try makeDAO()
        _ = try await dao.save(ReadingTime(id: 1, bookId: 10, date: "2025-01-01", readingTime: 300))
        _ = try await dao.save(ReadingTime(id: 2, bookId: 10, date: "2025-01-02", readingTime: 200))

        let total = try await dao.totalReadingTime(bookId: 10)
        #expect(total == 500)
    }

    @Test("Total across all books")
    func totalAcrossBooks() async throws {
        let dao = try makeDAO()
        _ = try await dao.save(ReadingTime(id: 1, bookId: 10, date: "2025-01-01", readingTime: 300))
        _ = try await dao.save(ReadingTime(id: 2, bookId: 20, date: "2025-01-01", readingTime: 150))

        let total = try await dao.totalReadingTimeAllBooks()
        #expect(total == 450)
    }

    @Test("Fetch by date")
    func fetchByDate() async throws {
        let dao = try makeDAO()
        _ = try await dao.save(ReadingTime(id: 1, bookId: 10, date: "2025-01-01", readingTime: 300))
        _ = try await dao.save(ReadingTime(id: 2, bookId: 10, date: "2025-01-02", readingTime: 200))

        let records = try await dao.fetchByDate("2025-01-01")
        #expect(records.count == 1)
        #expect(records[0].readingTime == 300)
    }
}
