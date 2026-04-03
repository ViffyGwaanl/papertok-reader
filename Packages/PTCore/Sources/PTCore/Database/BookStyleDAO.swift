import Foundation
import GRDB

public struct BookStyleDAO: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ style: BookStyle) async throws -> BookStyle {
        try await database.writer.write { db in
            try style.saved(db)
        }
    }

    public func fetchById(_ id: Int64) async throws -> BookStyle? {
        try await database.reader.read { db in
            try BookStyle.fetchOne(db, key: id)
        }
    }

    public func fetchAll() async throws -> [BookStyle] {
        try await database.reader.read { db in
            try BookStyle.fetchAll(db)
        }
    }

    public func delete(id: Int64) async throws {
        try await database.writer.write { db in
            _ = try BookStyle.deleteOne(db, key: id)
        }
    }
}
