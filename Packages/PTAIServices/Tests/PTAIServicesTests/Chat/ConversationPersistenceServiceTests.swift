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
