import Foundation
import GRDB

public struct ReadThemeDAO: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ theme: ReadTheme) async throws -> ReadTheme {
        try await database.writer.write { db in
            try theme.saved(db)
        }
    }

    public func fetchById(_ id: Int64) async throws -> ReadTheme? {
        try await database.reader.read { db in
            try ReadTheme.fetchOne(db, key: id)
        }
    }

    public func fetchAll() async throws -> [ReadTheme] {
        try await database.reader.read { db in
            try ReadTheme.fetchAll(db)
        }
    }

    public func delete(id: Int64) async throws {
        try await database.writer.write { db in
            _ = try ReadTheme.deleteOne(db, key: id)
        }
    }
}
