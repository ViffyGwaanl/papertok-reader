import Foundation
import GRDB

public struct Book: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "tb_books"

    public var id: Int64?
    public var title: String
    public var coverPath: String
    public var filePath: String
    public var lastReadPosition: String
    public var readingPercentage: Double
    public var author: String
    public var isDeleted: Bool
    public var description: String?
    public var rating: Double
    public var groupId: Int64
    public var md5: String?
    public var createTime: Date
    public var updateTime: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case coverPath = "cover_path"
        case filePath = "file_path"
        case lastReadPosition = "last_read_position"
        case readingPercentage = "reading_percentage"
        case author
        case isDeleted = "is_deleted"
        case description
        case rating
        case groupId = "group_id"
        case md5 = "file_md5"
        case createTime = "create_time"
        case updateTime = "update_time"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public static func placeholder(title: String, filePath: String) -> Book {
        let now = Date()
        return Book(
            id: nil,
            title: title,
            coverPath: "",
            filePath: filePath,
            lastReadPosition: "",
            readingPercentage: 0,
            author: "",
            isDeleted: false,
            description: nil,
            rating: 0,
            groupId: 0,
            md5: nil,
            createTime: now,
            updateTime: now
        )
    }
}
