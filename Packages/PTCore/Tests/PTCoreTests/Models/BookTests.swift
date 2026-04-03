import Testing
import GRDB
@testable import PTCore

@Suite("Book Model Tests")
struct BookTests {

    @Test("Table name is tb_books")
    func tableName() {
        #expect(Book.databaseTableName == "tb_books")
    }

    @Test("Placeholder has sensible defaults")
    func placeholder() {
        let book = Book.placeholder(title: "Test Book", filePath: "/path/to/book.epub")
        #expect(book.id == nil)
        #expect(book.title == "Test Book")
        #expect(book.filePath == "/path/to/book.epub")
        #expect(book.coverPath == "")
        #expect(book.lastReadPosition == "")
        #expect(book.readingPercentage == 0)
        #expect(book.author == "")
        #expect(book.isDeleted == false)
        #expect(book.description == nil)
        #expect(book.rating == 0)
        #expect(book.groupId == 0)
        #expect(book.md5 == nil)
    }

    @Test("Round-trip encode and decode via GRDB Row")
    func roundTrip() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "tb_books") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("cover_path", .text).notNull()
                t.column("file_path", .text).notNull()
                t.column("last_read_position", .text).notNull()
                t.column("reading_percentage", .double).notNull()
                t.column("author", .text).notNull()
                t.column("is_deleted", .boolean).notNull()
                t.column("description", .text)
                t.column("rating", .double).notNull()
                t.column("group_id", .integer).notNull()
                t.column("file_md5", .text)
                t.column("create_time", .datetime).notNull()
                t.column("update_time", .datetime).notNull()
            }

            var book = Book.placeholder(title: "Round Trip", filePath: "/test.epub")
            book.author = "Author"
            book.description = "A test book"
            book.rating = 4.5
            book.md5 = "abc123"
            try book.insert(db)

            let fetched = try Book.fetchOne(db)!
            #expect(fetched.id != nil)
            #expect(fetched.title == "Round Trip")
            #expect(fetched.filePath == "/test.epub")
            #expect(fetched.author == "Author")
            #expect(fetched.description == "A test book")
            #expect(fetched.rating == 4.5)
            #expect(fetched.md5 == "abc123")
            #expect(fetched.isDeleted == false)
            #expect(fetched.groupId == 0)
        }
    }
}
