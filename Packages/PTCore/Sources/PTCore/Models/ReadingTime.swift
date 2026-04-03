import Foundation
import GRDB

public struct ReadingTime: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "tb_reading_time"

    public var id: Int64?
    public var bookId: Int64
    public var date: String?
    public var readingTime: Int

    enum CodingKeys: String, CodingKey {
        case id
        case bookId = "book_id"
        case date
        case readingTime = "reading_time"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
