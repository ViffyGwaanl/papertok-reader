import Foundation
import GRDB

public struct BookTag: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "tb_book_tags"

    public var id: Int64?
    public var bookId: Int64
    public var tagId: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case bookId = "book_id"
        case tagId = "tag_id"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
