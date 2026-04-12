import Foundation
import GRDB
import PTCore
import PTAIServices

extension AppDatabase: @retroactive ToolDatabaseAccess {
    public func fetchBooks(query: String?, groupId: Int64?, limit: Int) async throws -> [[String: Any]] {
        try await reader.read { db in
            var request = Book
                .filter(Column("is_deleted") == false)
                .order(Column("update_time").desc)

            if let groupId {
                request = request.filter(Column("group_id") == groupId)
            }

            if let query, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                let escaped = query
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                let pattern = "%\(escaped)%"
                request = request.filter(
                    Column("title").like(pattern, escape: "\\") ||
                    Column("author").like(pattern, escape: "\\")
                )
            }

            return try request
                .limit(max(limit, 1))
                .fetchAll(db)
                .map(Self.bookMap(_:))
        }
    }

    public func fetchBookNotes(bookId: Int64?, keyword: String?, limit: Int) async throws -> [[String: Any]] {
        try await reader.read { db in
            var request = BookNote
                .order(Column("update_time").desc)

            if let bookId {
                request = request.filter(Column("book_id") == bookId)
            }

            if let keyword, keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                let pattern = "%\(keyword)%"
                request = request.filter(
                    Column("content").like(pattern) ||
                    Column("chapter").like(pattern) ||
                    Column("reader_note").like(pattern)
                )
            }

            return try request
                .limit(max(limit, 1))
                .fetchAll(db)
                .map(Self.noteMap(_:))
        }
    }

    public func fetchReadingTime(bookId: Int64?, since: Date?) async throws -> [[String: Any]] {
        try await reader.read { db in
            var request = ReadingTime.all()

            if let bookId {
                request = request.filter(Column("book_id") == bookId)
            }

            if let since {
                request = request.filter(Column("date") >= Self.dayFormatter.string(from: since))
            }

            return try request
                .order(Column("date").desc)
                .fetchAll(db)
                .map(Self.readingTimeMap(_:))
        }
    }

    public func fetchTags() async throws -> [[String: Any]] {
        try await reader.read { db in
            try Tag
                .order(Column("name").asc)
                .fetchAll(db)
                .map(Self.tagMap(_:))
        }
    }

    public func insertBookNote(_ fields: [String: Any]) async throws {
        let note = BookNote(
            bookId: fields["book_id"] as? Int64 ?? 0,
            content: fields["content"] as? String ?? "",
            cfi: fields["cfi"] as? String ?? "",
            chapter: fields["chapter"] as? String ?? "",
            type: fields["type"] as? String ?? "note",
            color: fields["color"] as? String ?? "",
            readerNote: fields["reader_note"] as? String,
            createTime: fields["create_time"] as? Date ?? Date(),
            updateTime: fields["update_time"] as? Date ?? Date()
        )

        try await writer.write { db in
            try note.insert(db)
        }
    }

    public func fetchBook(id: Int64) async throws -> [String : Any]? {
        try await reader.read { db in
            try Book
                .filter(Column("id") == id && Column("is_deleted") == false)
                .fetchOne(db)
                .map(Self.bookMap(_:))
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func bookMap(_ book: Book) -> [String: Any] {
        [
            "id": book.id as Any,
            "title": book.title,
            "author": book.author,
            "cover_path": book.coverPath,
            "file_path": book.filePath,
            "last_read_position": book.lastReadPosition,
            "reading_percentage": book.readingPercentage,
            "group_id": book.groupId,
            "file_md5": book.md5 as Any,
            "create_time": ISO8601DateFormatter().string(from: book.createTime),
            "update_time": ISO8601DateFormatter().string(from: book.updateTime),
        ]
    }

    private static func noteMap(_ note: BookNote) -> [String: Any] {
        var map: [String: Any] = [
            "id": note.id as Any,
            "book_id": note.bookId,
            "content": note.content,
            "cfi": note.cfi,
            "chapter": note.chapter,
            "type": note.type,
            "color": note.color,
            "update_time": ISO8601DateFormatter().string(from: note.updateTime),
        ]
        if let readerNote = note.readerNote {
            map["reader_note"] = readerNote
        }
        if let createTime = note.createTime {
            map["create_time"] = ISO8601DateFormatter().string(from: createTime)
        }
        return map
    }

    private static func readingTimeMap(_ readingTime: ReadingTime) -> [String: Any] {
        [
            "id": readingTime.id as Any,
            "book_id": readingTime.bookId,
            "date": readingTime.date as Any,
            "reading_time": readingTime.readingTime,
        ]
    }

    private static func tagMap(_ tag: Tag) -> [String: Any] {
        [
            "id": tag.id as Any,
            "name": tag.name,
            "color": tag.colorHex as Any,
        ]
    }
}
