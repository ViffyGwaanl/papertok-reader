import Foundation
import Testing
import GRDB
@testable import PTCore

@Suite("GroupDAO Tests")
struct GroupDAOTests {

    private func makeDAO() throws -> GroupDAO {
        let db = try AppDatabase.makeInMemory()
        return GroupDAO(database: db)
    }

    private func makeGroup(name: String, parentId: Int64? = nil) -> TbGroup {
        TbGroup(
            id: nil,
            name: name,
            parentId: parentId,
            isDeleted: false,
            createTime: Date(),
            updateTime: Date()
        )
    }

    @Test("Create and fetch groups")
    func createAndFetch() async throws {
        let dao = try makeDAO()
        let saved = try await dao.save(makeGroup(name: "Reading List"))
        #expect(saved.id != nil)

        let all = try await dao.fetchAll()
        #expect(all.count == 1)
        #expect(all[0].name == "Reading List")
    }

    @Test("Fetch children by parent id")
    func fetchChildren() async throws {
        let dao = try makeDAO()
        let parent = try await dao.save(makeGroup(name: "Parent"))
        _ = try await dao.save(makeGroup(name: "Child 1", parentId: parent.id!))
        _ = try await dao.save(makeGroup(name: "Child 2", parentId: parent.id!))
        _ = try await dao.save(makeGroup(name: "Other"))

        let children = try await dao.fetchChildren(parentId: parent.id!)
        #expect(children.count == 2)
    }

    @Test("Soft delete")
    func softDelete() async throws {
        let dao = try makeDAO()
        let group = try await dao.save(makeGroup(name: "ToDelete"))
        try await dao.softDelete(id: group.id!)

        let all = try await dao.fetchAll()
        #expect(all.isEmpty)
    }
}
