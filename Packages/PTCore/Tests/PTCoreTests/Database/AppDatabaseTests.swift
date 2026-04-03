import Testing
import GRDB
@testable import PTCore

@Suite("AppDatabase Tests")
struct AppDatabaseTests {

    @Test("All 8 tables exist after creation")
    func allTablesExist() throws {
        let db = try AppDatabase.makeInMemory()
        let tables: [String] = try db.reader.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%' ORDER BY name")
        }
        let expected = ["tb_book_tags", "tb_books", "tb_groups", "tb_notes", "tb_reading_time", "tb_styles", "tb_tags", "tb_themes"]
        #expect(tables == expected)
    }

    @Test("Schema version is 7")
    func schemaVersion() throws {
        let db = try AppDatabase.makeInMemory()
        let version: Int = try db.reader.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        }
        #expect(version == 7)
    }

    @Test("tb_books has expected columns")
    func booksColumns() throws {
        let db = try AppDatabase.makeInMemory()
        let columns: [String] = try db.reader.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(tb_books)").map { $0["name"] as String }
        }
        #expect(columns.contains("id"))
        #expect(columns.contains("title"))
        #expect(columns.contains("file_path"))
        #expect(columns.contains("reading_percentage"))
        #expect(columns.contains("is_deleted"))
        #expect(columns.contains("create_time"))
    }

    @Test("Can insert and fetch a Book")
    func insertAndFetchBook() throws {
        let db = try AppDatabase.makeInMemory()
        try db.writer.write { dbConn in
            let book = try Book.placeholder(title: "Test", filePath: "/test.epub").inserted(dbConn)
            #expect(book.id != nil)

            let fetched = try Book.fetchOne(dbConn, key: book.id!)
            #expect(fetched != nil)
            #expect(fetched?.title == "Test")
        }
    }
}
