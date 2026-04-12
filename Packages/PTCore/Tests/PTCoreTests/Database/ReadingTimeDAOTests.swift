import Testing
import GRDB
@testable import PTCore

@Suite("ReadingTimeDAO Tests")
struct ReadingTimeDAOTests {

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

    @Test("Insert and total time for book")
    func insertAndTotalTime() async throws {
        let db = try makeDB()
        try await insertBook(id: 10, database: db)
        let dao = ReadingTimeDAO(database: db)
        _ = try await dao.save(ReadingTime(id: nil, bookId: 10, date: "2025-01-01", readingTime: 300))
        _ = try await dao.save(ReadingTime(id: nil, bookId: 10, date: "2025-01-02", readingTime: 200))

        let total = try await dao.totalReadingTime(bookId: 10)
        #expect(total == 500)
    }

    @Test("Total across all books")
    func totalAcrossBooks() async throws {
        let db = try makeDB()
        try await insertBook(id: 10, database: db)
        try await insertBook(id: 20, database: db)
        let dao = ReadingTimeDAO(database: db)
        _ = try await dao.save(ReadingTime(id: nil, bookId: 10, date: "2025-01-01", readingTime: 300))
        _ = try await dao.save(ReadingTime(id: nil, bookId: 20, date: "2025-01-01", readingTime: 150))

        let total = try await dao.totalReadingTimeAllBooks()
        #expect(total == 450)
    }

    @Test("Fetch by date")
    func fetchByDate() async throws {
        let db = try makeDB()
        try await insertBook(id: 10, database: db)
        let dao = ReadingTimeDAO(database: db)
        _ = try await dao.save(ReadingTime(id: nil, bookId: 10, date: "2025-01-01", readingTime: 300))
        _ = try await dao.save(ReadingTime(id: nil, bookId: 10, date: "2025-01-02", readingTime: 200))

        let records = try await dao.fetchByDate("2025-01-01")
        #expect(records.count == 1)
        #expect(records[0].readingTime == 300)
    }

    @Test("Daily reading data grouped by book")
    func dailyReadingDataGroupedByBook() async throws {
        let db = try makeDB()
        try await insertBook(id: 10, database: db)
        try await insertBook(id: 20, database: db)
        let dao = ReadingTimeDAO(database: db)
        _ = try await dao.save(ReadingTime(id: nil, bookId: 10, date: "2025-01-01", readingTime: 300))
        _ = try await dao.save(ReadingTime(id: nil, bookId: 10, date: "2025-01-01", readingTime: 120))
        _ = try await dao.save(ReadingTime(id: nil, bookId: 10, date: "2025-01-02", readingTime: 60))
        _ = try await dao.save(ReadingTime(id: nil, bookId: 20, date: "2025-01-01", readingTime: 150))

        let grouped = try await dao.dailyReadingDataByBook()

        #expect(grouped[10]?["2025-01-01"] == 420)
        #expect(grouped[10]?["2025-01-02"] == 60)
        #expect(grouped[20]?["2025-01-01"] == 150)
    }

    @Test("Add reading time merges the same book day")
    func addReadingTimeMergesTheSameBookDay() async throws {
        let db = try makeDB()
        try await insertBook(id: 10, database: db)
        let dao = ReadingTimeDAO(database: db)

        try await dao.addReadingTime(bookId: 10, dayKey: "2025-01-01", readingTime: 300)
        try await dao.addReadingTime(bookId: 10, dayKey: "2025-01-01", readingTime: 120)

        let records = try await dao.fetchByDate("2025-01-01")
        #expect(records.count == 1)
        #expect(records[0].bookId == 10)
        #expect(records[0].readingTime == 420)
    }
}
