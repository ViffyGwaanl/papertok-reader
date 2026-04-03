import Foundation
import GRDB

public struct BookNote: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "tb_notes"

    public var id: Int64?
    public var bookId: Int64
    public var content: String
    public var cfi: String
    public var chapter: String
    public var type: String
    public var color: String
    public var readerNote: String?
    public var createTime: Date?
    public var updateTime: Date

    enum CodingKeys: String, CodingKey {
        case id
        case bookId = "book_id"
        case content
        case cfi
        case chapter
        case type
        case color
        case readerNote = "reader_note"
        case createTime = "create_time"
        case updateTime = "update_time"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
