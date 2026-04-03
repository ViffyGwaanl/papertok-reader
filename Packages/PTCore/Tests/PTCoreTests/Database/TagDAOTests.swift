import Testing
import GRDB
@testable import PTCore

@Suite("TagDAO Tests")
struct TagDAOTests {

    private func makeDAO() throws -> TagDAO {
        let db = try AppDatabase.makeInMemory()
        return TagDAO(database: db)
    }

    @Test("CRUD tags")
    func crudTags() async throws {
        let dao = try makeDAO()

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
        let dao = try makeDAO()
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
        let dao = try makeDAO()
        let tag = try await dao.save(Tag(id: nil, name: "Drama", colorHex: nil))
        try await dao.attachTag(tagId: tag.id!, toBookId: 1)

        try await dao.delete(id: tag.id!)

        let tagIds = try await dao.fetchTagIds(forBookId: 1)
        #expect(tagIds.isEmpty)
    }
}
