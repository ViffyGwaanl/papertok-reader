import Foundation
import GRDB

public struct Tag: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "tb_tags"

    public var id: Int64?
    public var name: String
    public var colorHex: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex = "color"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
