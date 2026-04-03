import Foundation
import GRDB

public struct GroupDAO: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ group: TbGroup) async throws -> TbGroup {
        try await database.writer.write { db in
            try group.saved(db)
        }
    }

    public func fetchAll() async throws -> [TbGroup] {
        try await database.reader.read { db in
            try TbGroup.filter(Column("is_deleted") == false).fetchAll(db)
        }
    }

    public func fetchChildren(parentId: Int64) async throws -> [TbGroup] {
        try await database.reader.read { db in
            try TbGroup
                .filter(Column("parent_id") == parentId && Column("is_deleted") == false)
                .fetchAll(db)
        }
    }

    public func softDelete(id: Int64) async throws {
        try await database.writer.write { db in
            if var group = try TbGroup.fetchOne(db, key: id) {
                group.isDeleted = true
                try group.update(db)
            }
        }
    }
}
