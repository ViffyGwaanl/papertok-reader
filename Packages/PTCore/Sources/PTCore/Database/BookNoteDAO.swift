import Foundation
import GRDB

public struct BookNoteDAO: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ note: BookNote) async throws -> BookNote {
        try await database.writer.write { db in
            try note.saved(db)
        }
    }

    public func fetchByBookId(_ bookId: Int64) async throws -> [BookNote] {
        try await database.reader.read { db in
            try BookNote
                .filter(Column("book_id") == bookId)
                .order(Column("create_time").desc)
                .fetchAll(db)
        }
    }

    public func delete(id: Int64) async throws {
        try await database.writer.write { db in
            _ = try BookNote.deleteOne(db, key: id)
        }
    }

    public func countNotesAndBooks() async throws -> (Int, Int) {
        try await database.reader.read { db in
            let totalNotes = try BookNote.fetchCount(db)
            let booksWithNotes = try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT book_id) FROM tb_notes") ?? 0
            return (totalNotes, booksWithNotes)
        }
    }

    public func search(keyword: String, bookId: Int64? = nil) async throws -> [BookNote] {
        let pattern = "%\(keyword)%"
        return try await database.reader.read { db in
            var request = BookNote.filter(
                Column("content").like(pattern) ||
                Column("chapter").like(pattern) ||
                Column("reader_note").like(pattern)
            )
            if let bookId {
                request = request.filter(Column("book_id") == bookId)
            }
            return try request.fetchAll(db)
        }
    }
}
