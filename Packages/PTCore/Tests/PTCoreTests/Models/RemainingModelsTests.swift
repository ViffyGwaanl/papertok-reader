import Foundation
import Testing
import GRDB
@testable import PTCore

@Suite("ReadingTime Model Tests")
struct ReadingTimeTests {

    @Test("Table name is tb_reading_time")
    func tableName() {
        #expect(ReadingTime.databaseTableName == "tb_reading_time")
    }

    @Test("Round-trip encode and decode via GRDB Row")
    func roundTrip() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "tb_reading_time") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("book_id", .integer).notNull()
                t.column("date", .text)
                t.column("reading_time", .integer).notNull()
            }

            var record = ReadingTime(id: nil, bookId: 42, date: "2026-04-02", readingTime: 3600)
            try record.insert(db)

            let fetched = try ReadingTime.fetchOne(db)!
            #expect(fetched.id != nil)
            #expect(fetched.bookId == 42)
            #expect(fetched.date == "2026-04-02")
            #expect(fetched.readingTime == 3600)
        }
    }
}

@Suite("Tag Model Tests")
struct TagTests {

    @Test("Table name is tb_tags")
    func tableName() {
        #expect(Tag.databaseTableName == "tb_tags")
    }

    @Test("Round-trip encode and decode via GRDB Row")
    func roundTrip() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "tb_tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("color", .text)
            }

            var tag = Tag(id: nil, name: "Fiction", colorHex: "FF5733")
            try tag.insert(db)

            let fetched = try Tag.fetchOne(db)!
            #expect(fetched.id != nil)
            #expect(fetched.name == "Fiction")
            #expect(fetched.colorHex == "FF5733")
        }
    }
}

@Suite("BookTag Model Tests")
struct BookTagTests {

    @Test("Table name is tb_book_tags")
    func tableName() {
        #expect(BookTag.databaseTableName == "tb_book_tags")
    }

    @Test("Round-trip encode and decode via GRDB Row")
    func roundTrip() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "tb_book_tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("book_id", .integer).notNull()
                t.column("tag_id", .integer).notNull()
            }

            var bookTag = BookTag(id: nil, bookId: 1, tagId: 5)
            try bookTag.insert(db)

            let fetched = try BookTag.fetchOne(db)!
            #expect(fetched.id != nil)
            #expect(fetched.bookId == 1)
            #expect(fetched.tagId == 5)
        }
    }
}

@Suite("TbGroup Model Tests")
struct TbGroupTests {

    @Test("Table name is tb_groups")
    func tableName() {
        #expect(TbGroup.databaseTableName == "tb_groups")
    }

    @Test("Round-trip encode and decode via GRDB Row")
    func roundTrip() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "tb_groups") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("parent_id", .integer)
                t.column("is_deleted", .boolean).notNull()
                t.column("create_time", .datetime).notNull()
                t.column("update_time", .datetime).notNull()
            }

            let now = Date()
            var group = TbGroup(
                id: nil,
                name: "My Shelf",
                parentId: nil,
                isDeleted: false,
                createTime: now,
                updateTime: now
            )
            try group.insert(db)

            let fetched = try TbGroup.fetchOne(db)!
            #expect(fetched.id != nil)
            #expect(fetched.name == "My Shelf")
            #expect(fetched.parentId == nil)
            #expect(fetched.isDeleted == false)
        }
    }
}
