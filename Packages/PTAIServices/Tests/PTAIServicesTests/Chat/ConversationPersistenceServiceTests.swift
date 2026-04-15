import XCTest
@testable import PTAIServices

final class ConversationPersistenceServiceTests: XCTestCase {
    private var tempDir: URL!
    private var service: ConversationPersistenceService!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConvPersistTest-\(UUID().uuidString)")
        service = ConversationPersistenceService(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSaveAndLoad() throws {
        var tree = ConversationTree(systemPrompt: "Test prompt")
        tree.append(.user("Hello"))
        tree.append(.assistant("Hi there"))

        let conversation = ConversationPersistenceService.PersistedConversation(
            id: "test-1",
            title: "Test Conversation",
            systemPrompt: "Test prompt",
            tree: tree,
            providerId: "openai",
            modelId: "gpt-4o"
        )

        try service.save(conversation)

        let loaded = try service.load(id: "test-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, "test-1")
        XCTAssertEqual(loaded?.title, "Test Conversation")
        XCTAssertEqual(loaded?.providerId, "openai")
        XCTAssertEqual(loaded?.modelId, "gpt-4o")

        let messages = loaded?.tree.activeMessages() ?? []
        XCTAssertEqual(messages.count, 3) // system + user + assistant
        XCTAssertEqual(messages[1].textContent, "Hello")
        XCTAssertEqual(messages[2].textContent, "Hi there")
    }

    func testLoadNonexistent() throws {
        let loaded = try service.load(id: "nonexistent")
        XCTAssertNil(loaded)
    }

    func testListSummaries() throws {
        for i in 0..<3 {
            var tree = ConversationTree(systemPrompt: "System")
            tree.append(.user("Message \(i)"))
            tree.append(.assistant("Response \(i)"))
            let conv = ConversationPersistenceService.PersistedConversation(
                id: "conv-\(i)",
                title: "Conversation \(i)",
                systemPrompt: "System",
                tree: tree
            )
            try service.save(conv)
        }

        let summaries = try service.listSummaries()
        XCTAssertEqual(summaries.count, 3)
        // Summaries should be sorted by updatedAt descending (all same here)
        for summary in summaries {
            XCTAssertEqual(summary.messageCount, 3) // system + user + assistant
            XCTAssertFalse(summary.lastMessagePreview.isEmpty)
        }
    }

    func testDelete() throws {
        var tree = ConversationTree(systemPrompt: "System")
        tree.append(.user("Delete me"))
        let conv = ConversationPersistenceService.PersistedConversation(
            id: "to-delete",
            title: "Deletable",
            systemPrompt: "System",
            tree: tree
        )
        try service.save(conv)
        XCTAssertNotNil(try service.load(id: "to-delete"))

        try service.delete(id: "to-delete")
        XCTAssertNil(try service.load(id: "to-delete"))
    }

    // MARK: - W2.1a: isPinned / bookId / legacy migration

    func testPersistsAndLoadsIsPinnedField() throws {
        let tree = ConversationTree(systemPrompt: "s")
        let pinned = ConversationPersistenceService.PersistedConversation(
            id: "pinned-1", title: "Pinned", systemPrompt: "s", tree: tree, isPinned: true
        )
        try service.save(pinned)
        let loaded = try XCTUnwrap(service.load(id: "pinned-1"))
        XCTAssertTrue(loaded.isPinned)

        let unpinned = ConversationPersistenceService.PersistedConversation(
            id: "pinned-2", title: "Unpinned", systemPrompt: "s", tree: tree, isPinned: false
        )
        try service.save(unpinned)
        let loaded2 = try XCTUnwrap(service.load(id: "pinned-2"))
        XCTAssertFalse(loaded2.isPinned)
    }

    func testPersistsAndLoadsBookIdField() throws {
        let tree = ConversationTree(systemPrompt: "s")
        let withBook = ConversationPersistenceService.PersistedConversation(
            id: "book-1", title: "B", systemPrompt: "s", tree: tree, bookId: "book-123"
        )
        try service.save(withBook)
        let loaded = try XCTUnwrap(service.load(id: "book-1"))
        XCTAssertEqual(loaded.bookId, "book-123")

        let global = ConversationPersistenceService.PersistedConversation(
            id: "book-2", title: "G", systemPrompt: "s", tree: tree, bookId: nil
        )
        try service.save(global)
        let loaded2 = try XCTUnwrap(service.load(id: "book-2"))
        XCTAssertNil(loaded2.bookId)
    }

    func testOldFormatWithoutNewFieldsLoadsWithDefaults() throws {
        // Save a normal conversation, then strip the new-in-W2.1a keys from the JSON on disk
        // so `load` must exercise the `decodeIfPresent` backward-compat path.
        var tree = ConversationTree(systemPrompt: "sys")
        tree.append(.user("hi"))
        let conv = ConversationPersistenceService.PersistedConversation(
            id: "legacy-1", title: "Legacy", systemPrompt: "sys", tree: tree
        )
        try service.save(conv)

        let fileURL = tempDir.appendingPathComponent("legacy-1.json")
        let data = try Data(contentsOf: fileURL)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "isPinned")
        object.removeValue(forKey: "bookId")
        XCTAssertNil(object["isPinned"])
        XCTAssertNil(object["bookId"])
        let stripped = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try stripped.write(to: fileURL)

        let loaded = try XCTUnwrap(service.load(id: "legacy-1"))
        XCTAssertEqual(loaded.id, "legacy-1")
        XCTAssertFalse(loaded.isPinned)
        XCTAssertNil(loaded.bookId)
    }

    func testLegacyUserDefaultsPinsMigrateOnFirstListSummaries() throws {
        let suiteName = "ConvPersistTest.migrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["uuid-1", "uuid-2"], forKey: ConversationPersistenceService.legacyPinnedConversationsKey)

        let migratingService = ConversationPersistenceService(directory: tempDir, userDefaults: defaults)
        for id in ["uuid-1", "uuid-2"] {
            let conv = ConversationPersistenceService.PersistedConversation(
                id: id, title: id, systemPrompt: "s", tree: ConversationTree(systemPrompt: "s"), isPinned: false
            )
            try migratingService.save(conv)
        }

        _ = try migratingService.listSummaries()

        let a = try XCTUnwrap(migratingService.load(id: "uuid-1"))
        let b = try XCTUnwrap(migratingService.load(id: "uuid-2"))
        XCTAssertTrue(a.isPinned)
        XCTAssertTrue(b.isPinned)
        XCTAssertNil(defaults.array(forKey: ConversationPersistenceService.legacyPinnedConversationsKey))
        XCTAssertTrue(defaults.bool(forKey: ConversationPersistenceService.legacyPinnedMigrationMarkerKey))
    }

    func testMigrationIsIdempotent() throws {
        let suiteName = "ConvPersistTest.idempotent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Marker already set: the migration must not touch the legacy key even if present.
        defaults.set(true, forKey: ConversationPersistenceService.legacyPinnedMigrationMarkerKey)
        defaults.set(["uuid-zzz"], forKey: ConversationPersistenceService.legacyPinnedConversationsKey)

        let svc = ConversationPersistenceService(directory: tempDir, userDefaults: defaults)
        _ = try svc.listSummaries()

        XCTAssertEqual(
            defaults.array(forKey: ConversationPersistenceService.legacyPinnedConversationsKey) as? [String],
            ["uuid-zzz"]
        )
        XCTAssertTrue(defaults.bool(forKey: ConversationPersistenceService.legacyPinnedMigrationMarkerKey))
    }

    func testDeleteAll() throws {
        for i in 0..<3 {
            let tree = ConversationTree(systemPrompt: "System")
            let conv = ConversationPersistenceService.PersistedConversation(
                id: "conv-\(i)",
                title: "C\(i)",
                systemPrompt: "System",
                tree: tree
            )
            try service.save(conv)
        }
        XCTAssertEqual(try service.listSummaries().count, 3)

        try service.deleteAll()
        XCTAssertEqual(try service.listSummaries().count, 0)
    }
}
