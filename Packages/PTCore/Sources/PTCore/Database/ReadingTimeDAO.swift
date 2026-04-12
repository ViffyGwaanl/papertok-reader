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

    public func addReadingTime(bookId: Int64, dayKey: String, readingTime: Int) async throws {
        guard readingTime > 0 else { return }
        try await database.writer.write { db in
            let existingID = try Int64.fetchOne(
                db,
                sql: """
                    SELECT id
                    FROM tb_reading_time
                    WHERE book_id = ? AND date = ?
                    LIMIT 1
                    """,
                arguments: [bookId, dayKey]
            )

            if let existingID {
                try db.execute(
                    sql: """
                        UPDATE tb_reading_time
                        SET reading_time = reading_time + ?
                        WHERE id = ?
                        """,
                    arguments: [readingTime, existingID]
                )
            } else {
                let record = ReadingTime(bookId: bookId, date: dayKey, readingTime: readingTime)
                try record.insert(db)
            }
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

    /// Returns daily reading totals (in seconds) for a date range, keyed by "yyyy-MM-dd".
    public func dailyReadingData(from startDate: String, to endDate: String) async throws -> [String: Int] {
        try await database.reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT date, COALESCE(SUM(reading_time), 0) AS total
                    FROM tb_reading_time
                    WHERE date >= ? AND date <= ?
                    GROUP BY date
                    """,
                arguments: [startDate, endDate]
            )
            var result: [String: Int] = [:]
            for row in rows {
                if let date: String = row["date"], let total: Int = row["total"] {
                    result[date] = total
                }
            }
            return result
        }
    }

    /// Returns all daily reading totals (in seconds), keyed by "yyyy-MM-dd".
    public func dailyReadingData() async throws -> [String: Int] {
        try await database.reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT date, COALESCE(SUM(reading_time), 0) AS total
                    FROM tb_reading_time
                    GROUP BY date
                    """
            )
            var result: [String: Int] = [:]
            for row in rows {
                if let date: String = row["date"], let total: Int = row["total"] {
                    result[date] = total
                }
            }
            return result
        }
    }

    /// Returns daily reading totals (in seconds) grouped by book ID, keyed by "yyyy-MM-dd".
    public func dailyReadingDataByBook() async throws -> [Int64: [String: Int]] {
        try await database.reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT book_id, date, COALESCE(SUM(reading_time), 0) AS total
                    FROM tb_reading_time
                    GROUP BY book_id, date
                    """
            )
            var result: [Int64: [String: Int]] = [:]
            for row in rows {
                guard let bookId: Int64 = row["book_id"],
                      let date: String = row["date"],
                      let total: Int = row["total"] else {
                    continue
                }
                result[bookId, default: [:]][date] = total
            }
            return result
        }
    }
}
