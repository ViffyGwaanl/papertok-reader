import Foundation
import Testing
import GRDB
@testable import PTCore

@Suite("BookNote Model Tests")
struct BookNoteTests {

    @Test("Table name is tb_notes")
    func tableName() {
        #expect(BookNote.databaseTableName == "tb_notes")
    }

    @Test("Round-trip encode and decode via GRDB Row")
    func roundTrip() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "tb_notes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("book_id", .integer).notNull()
                t.column("content", .text).notNull()
                t.column("cfi", .text).notNull()
                t.column("chapter", .text).notNull()
                t.column("type", .text).notNull()
                t.column("color", .text).notNull()
                t.column("reader_note", .text)
                t.column("create_time", .datetime)
                t.column("update_time", .datetime).notNull()
            }

            var note = BookNote(
                id: nil,
                bookId: 1,
                content: "Important passage",
                cfi: "epubcfi(/6/4!/4/2/1:0)",
                chapter: "Chapter 1",
                type: "highlight",
                color: "FFD700",
                readerNote: "My note",
                createTime: Date(),
                updateTime: Date()
            )
            try note.insert(db)

            let fetched = try BookNote.fetchOne(db)!
            #expect(fetched.id != nil)
            #expect(fetched.bookId == 1)
            #expect(fetched.content == "Important passage")
            #expect(fetched.cfi == "epubcfi(/6/4!/4/2/1:0)")
            #expect(fetched.chapter == "Chapter 1")
            #expect(fetched.type == "highlight")
            #expect(fetched.color == "FFD700")
            #expect(fetched.readerNote == "My note")
        }
    }
}
