import Foundation
import Testing
import GRDB
@testable import PTCore

@Suite("TagDAO Tests")
struct TagDAOTests {

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.makeInMemory()
    }

    /// Insert a parent book so FK constraints are satisfied.
    private func insertBook(id: Int64, database: AppDatabase) async throws {
        let dao = BookDAO(database: database)
        var book = Book.placeholder(title: "Book \(id)", filePath: "/book\(id).pdf")
        book.id = id
        _ = try await dao.save(book)
    }

    @Test("CRUD tags")
    func crudTags() async throws {
        let db = try makeDB()
        let dao = TagDAO(database: db)

        // Create
        let saved = try await dao.save(Tag(id: nil, name: "Fiction", colorHex: "#FF0000"))
        #expect(saved.id != nil)

        // Read
        let all = try await dao.fetchAll()
        #expect(all.count == 1)
        #expect(all[0].name == "Fiction")

        // Delete
        try await dao.delete(id: saved.id!)
        let afterDelete = try await dao.fetchAll()
        #expect(afterDelete.isEmpty)
    }

    @Test("Attach and detach book tags")
    func attachDetachBookTags() async throws {
        let db = try makeDB()
        try await insertBook(id: 1, database: db)
        try await insertBook(id: 2, database: db)
        let dao = TagDAO(database: db)
        let tag = try await dao.save(Tag(id: nil, name: "Sci-Fi", colorHex: nil))

        try await dao.attachTag(tagId: tag.id!, toBookId: 1)
        try await dao.attachTag(tagId: tag.id!, toBookId: 2)

        var tagIds = try await dao.fetchTagIds(forBookId: 1)
        #expect(tagIds == [tag.id!])

        try await dao.detachTag(tagId: tag.id!, fromBookId: 1)
        tagIds = try await dao.fetchTagIds(forBookId: 1)
        #expect(tagIds.isEmpty)

        // Book 2 still has the tag
        let book2Tags = try await dao.fetchTagIds(forBookId: 2)
        #expect(book2Tags == [tag.id!])
    }

    @Test("Deleting a tag also removes book_tags")
    func deleteTagCascades() async throws {
        let db = try makeDB()
        try await insertBook(id: 1, database: db)
        let dao = TagDAO(database: db)
        let tag = try await dao.save(Tag(id: nil, name: "Drama", colorHex: nil))
        try await dao.attachTag(tagId: tag.id!, toBookId: 1)

        try await dao.delete(id: tag.id!)

        let tagIds = try await dao.fetchTagIds(forBookId: 1)
        #expect(tagIds.isEmpty)
    }

    @Test("fetchAll uses pinyin order for Chinese locales")
    func fetchAllUsesPinyinOrderForChinese() async throws {
        let db = try makeDB()
        let dao = TagDAO(database: db)
        _ = try await dao.save(Tag(id: nil, name: "李白", colorHex: nil))
        _ = try await dao.save(Tag(id: nil, name: "杜甫", colorHex: nil))
        _ = try await dao.save(Tag(id: nil, name: "王维", colorHex: nil))

        let names = try await dao.fetchAll(locale: Locale(identifier: "zh-Hans")).map(\.name)
        #expect(names == ["杜甫", "李白", "王维"])
    }
}
