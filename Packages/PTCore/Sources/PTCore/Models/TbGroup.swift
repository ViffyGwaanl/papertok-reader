import Foundation
import GRDB

public struct TbGroup: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "tb_groups"

    public var id: Int64?
    public var name: String
    public var parentId: Int64?
    public var isDeleted: Bool
    public var createTime: Date
    public var updateTime: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentId = "parent_id"
        case isDeleted = "is_deleted"
        case createTime = "create_time"
        case updateTime = "update_time"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
