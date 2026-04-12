import Foundation
import GRDB

public enum GroupDAOError: Error {
    case notFound(Int64)
}

public struct GroupDAO: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func create(name: String, parentId: Int64? = nil) async throws -> TbGroup {
        try await database.writer.write { db in
            let now = Date()
            return try TbGroup(
                id: nil,
                name: name,
                parentId: parentId,
                isDeleted: false,
                createTime: now,
                updateTime: now
            ).saved(db)
        }
    }

    public func rename(id: Int64, to name: String) async throws -> TbGroup {
        try await database.writer.write { db in
            guard var group = try TbGroup.fetchOne(db, key: id) else {
                throw GroupDAOError.notFound(id)
            }
            group.name = name
            group.updateTime = Date()
            try group.update(db)
            return group
        }
    }

    public func save(_ group: TbGroup) async throws -> TbGroup {
        try await database.writer.write { db in
            try group.saved(db)
        }
    }

    public func fetchById(_ id: Int64) async throws -> TbGroup? {
        try await database.reader.read { db in
            try TbGroup.fetchOne(db, key: id)
        }
    }

    public func fetchAll() async throws -> [TbGroup] {
        try await database.reader.read { db in
            try TbGroup
                .filter(Column("is_deleted") == false)
                .fetchAll(db)
                .sorted { lhs, rhs in
                    switch (lhs.parentId, rhs.parentId) {
                    case (nil, .some):
                        return true
                    case (.some, nil):
                        return false
                    default:
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                }
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
                group.updateTime = Date()
                try group.update(db)
            }
        }
    }

    public func reparentChildren(fromParentId parentId: Int64, toParentId newParentId: Int64?) async throws {
        try await database.writer.write { db in
            let groups = try TbGroup
                .filter(Column("parent_id") == parentId && Column("is_deleted") == false)
                .fetchAll(db)

            for var group in groups {
                group.parentId = newParentId
                group.updateTime = Date()
                try group.update(db)
            }
        }
    }
}
