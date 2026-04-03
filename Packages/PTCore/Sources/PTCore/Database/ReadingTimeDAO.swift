import Foundation
import GRDB

public struct ReadingTimeDAO: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ record: ReadingTime) async throws -> ReadingTime {
        try await database.writer.write { db in
            try record.saved(db)
        }
    }

    public func totalReadingTime(bookId: Int64) async throws -> Int {
        try await database.reader.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(reading_time), 0) FROM tb_reading_time WHERE book_id = ?",
                arguments: [bookId]
            ) ?? 0
        }
    }

    public func totalReadingTimeAllBooks() async throws -> Int {
        try await database.reader.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(reading_time), 0) FROM tb_reading_time"
            ) ?? 0
        }
    }

    public func fetchByDate(_ date: String) async throws -> [ReadingTime] {
        try await database.reader.read { db in
            try ReadingTime.filter(Column("date") == date).fetchAll(db)
        }
    }
}
