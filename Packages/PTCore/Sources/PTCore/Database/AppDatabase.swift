import Foundation
import GRDB

public final class AppDatabase: Sendable {
    private let _writer: any DatabaseWriter

    public var writer: any DatabaseWriter { _writer }
    public var reader: any DatabaseReader { _writer }

    private init(writer: any DatabaseWriter) throws {
        self._writer = writer
        var migrator = Self.migrator
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        try migrator.migrate(writer)
    }

    // MARK: - Factory Methods

    public static func makeInMemory() throws -> AppDatabase {
        let queue = try DatabaseQueue()
        return try AppDatabase(writer: queue)
    }

    public static func make(at path: String) throws -> AppDatabase {
        let pool = try DatabasePool(path: path)
        return try AppDatabase(writer: pool)
    }

    // MARK: - Migrations

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v0-initial") { db in
            // tb_books
            try db.create(table: "tb_books") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text)
                t.column("cover_path", .text)
                t.column("file_path", .text)
                t.column("last_read_position", .text)
                t.column("reading_percentage", .double).defaults(to: 0)
                t.column("author", .text)
                t.column("is_deleted", .integer).defaults(to: 0)
                t.column("description", .text)
                t.column("rating", .double).defaults(to: 0)
                t.column("group_id", .integer).defaults(to: 0)
                t.column("file_md5", .text)
                t.column("create_time", .datetime)
                t.column("update_time", .datetime)
            }

            // tb_notes
            try db.create(table: "tb_notes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("book_id", .integer).notNull().references("tb_books", onDelete: .cascade)
                t.column("content", .text)
                t.column("cfi", .text)
                t.column("chapter", .text)
                t.column("type", .text)
                t.column("color", .text)
                t.column("reader_note", .text)
                t.column("create_time", .datetime)
                t.column("update_time", .datetime)
            }

            // tb_themes
            try db.create(table: "tb_themes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("background_color", .text)
                t.column("text_color", .text)
                t.column("background_image_path", .text)
            }

            // tb_styles
            try db.create(table: "tb_styles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("font_size", .double)
                t.column("font_family", .text)
                t.column("line_height", .double)
                t.column("letter_spacing", .double)
                t.column("word_spacing", .double)
                t.column("paragraph_spacing", .double)
                t.column("side_margin", .double)
                t.column("top_margin", .double)
                t.column("bottom_margin", .double)
            }

            // tb_reading_time
            try db.create(table: "tb_reading_time") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("book_id", .integer).notNull().references("tb_books", onDelete: .cascade)
                t.column("date", .text)
                t.column("reading_time", .integer)
            }

            // tb_groups
            try db.create(table: "tb_groups") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text)
                t.column("parent_id", .integer).references("tb_groups", column: "id")
                t.column("is_deleted", .integer).defaults(to: 0)
                t.column("create_time", .datetime)
                t.column("update_time", .datetime)
            }

            // tb_tags
            try db.create(table: "tb_tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("color", .text)
            }

            // tb_book_tags
            try db.create(table: "tb_book_tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("book_id", .integer).notNull().references("tb_books", onDelete: .cascade)
                t.column("tag_id", .integer).notNull().references("tb_tags", onDelete: .cascade)
            }

            // Indexes for frequently queried columns
            try db.create(index: "idx_books_file_md5", on: "tb_books", columns: ["file_md5"])
            try db.create(index: "idx_books_is_deleted", on: "tb_books", columns: ["is_deleted"])
            try db.create(index: "idx_notes_book_id", on: "tb_notes", columns: ["book_id"])
            try db.create(index: "idx_reading_time_book_id", on: "tb_reading_time", columns: ["book_id"])
            try db.create(index: "idx_book_tags_book_id", on: "tb_book_tags", columns: ["book_id"])
            try db.create(index: "idx_book_tags_tag_id", on: "tb_book_tags", columns: ["tag_id"])

            // Set schema version
            try db.execute(sql: "PRAGMA user_version = 7")
        }

        return migrator
    }
}
