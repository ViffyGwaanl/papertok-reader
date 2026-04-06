import Foundation
import GRDB

public struct BookDAO: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ book: Book) async throws -> Book {
        try await database.writer.write { db in
            try book.saved(db)
        }
    }

    public func fetchById(_ id: Int64) async throws -> Book? {
        try await database.reader.read { db in
            try Book.fetchOne(db, key: id)
        }
    }

    public func fetchAll() async throws -> [Book] {
        try await database.reader.read { db in
            try Book.filter(Column("is_deleted") == false).fetchAll(db)
        }
    }

    public func search(query: String) async throws -> [Book] {
        // Escape LIKE wildcards in user input
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"
        return try await database.reader.read { db in
            try Book
                .filter(Column("is_deleted") == false)
                .filter(
                    Column("title").like(pattern, escape: "\\") ||
                    Column("author").like(pattern, escape: "\\")
                )
                .fetchAll(db)
        }
    }

    public func fetchByMD5(_ md5: String) async throws -> Book? {
        try await database.reader.read { db in
            try Book
                .filter(Column("file_md5") == md5)
                .filter(Column("is_deleted") == false)
                .fetchOne(db)
        }
    }

    public func softDelete(id: Int64) async throws {
        try await database.writer.write { db in
            if var book = try Book.fetchOne(db, key: id) {
                book.isDeleted = true
                try book.update(db)
            }
        }
    }
}
