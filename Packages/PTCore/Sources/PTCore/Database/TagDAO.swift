import Foundation
import GRDB

public struct TagDAO: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ tag: Tag) async throws -> Tag {
        try await database.writer.write { db in
            try tag.saved(db)
        }
    }

    public func fetchAll() async throws -> [Tag] {
        try await database.reader.read { db in
            try Tag.fetchAll(db)
        }
    }

    public func delete(id: Int64) async throws {
        try await database.writer.write { db in
            _ = try BookTag.filter(Column("tag_id") == id).deleteAll(db)
            _ = try Tag.deleteOne(db, key: id)
        }
    }

    public func attachTag(tagId: Int64, toBookId bookId: Int64) async throws {
        try await database.writer.write { db in
            _ = try BookTag(id: nil, bookId: bookId, tagId: tagId).inserted(db)
        }
    }

    public func detachTag(tagId: Int64, fromBookId bookId: Int64) async throws {
        try await database.writer.write { db in
            _ = try BookTag
                .filter(Column("tag_id") == tagId && Column("book_id") == bookId)
                .deleteAll(db)
        }
    }

    public func fetchTagIds(forBookId bookId: Int64) async throws -> [Int64] {
        try await database.reader.read { db in
            try Int64.fetchAll(
                db,
                sql: "SELECT tag_id FROM tb_book_tags WHERE book_id = ?",
                arguments: [bookId]
            )
        }
    }
}
