import Foundation
import GRDB

public enum TagDAOError: Error {
    case notFound(Int64)
}

public struct TagDAO: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func create(name: String, colorHex: String?) async throws -> Tag {
        try await database.writer.write { db in
            try Tag(id: nil, name: name, colorHex: colorHex).saved(db)
        }
    }

    public func update(id: Int64, name: String, colorHex: String?) async throws -> Tag {
        try await database.writer.write { db in
            guard var tag = try Tag.fetchOne(db, key: id) else {
                throw TagDAOError.notFound(id)
            }
            tag.name = name
            tag.colorHex = colorHex
            try tag.update(db)
            return tag
        }
    }

    public func save(_ tag: Tag) async throws -> Tag {
        try await database.writer.write { db in
            try tag.saved(db)
        }
    }

    public func fetchAll(locale: Locale = .autoupdatingCurrent) async throws -> [Tag] {
        try await database.reader.read { db in
            try Tag.fetchAll(db)
                .sorted {
                    LocalizedSort.isAscending($0.name, $1.name, locale: locale)
                }
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
            let existing = try BookTag
                .filter(Column("book_id") == bookId && Column("tag_id") == tagId)
                .fetchOne(db)
            guard existing == nil else { return }
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
