import Testing
import Foundation
@testable import PTAIServices

@Suite("ConversationTree")
struct ConversationTreeTests {
    @Test("Creates empty tree with system message")
    func emptyTree() {
        let tree = ConversationTree(systemPrompt: "You are helpful")
        #expect(tree.nodes.count == 1)
        #expect(tree.nodes[tree.rootId]!.role == .system)
    }

    @Test("Appends messages to active branch")
    func appendMessages() {
        var tree = ConversationTree(systemPrompt: "System")
        tree.append(.user("Hello"))
        tree.append(.assistant("Hi"))
        let messages = tree.activeMessages()
        #expect(messages.count == 3)
        #expect(messages[1].role == .user)
        #expect(messages[2].role == .assistant)
    }

    @Test("Creates branch on regeneration")
    func branching() {
        var tree = ConversationTree(systemPrompt: "System")
        tree.append(.user("Hello"))
        tree.append(.assistant("Response A"))
        let parentId = tree.activeLeafParentId()!
        tree.addVariant(parentId: parentId, message: .assistant("Response B"))
        #expect(tree.activeMessages().last?.textContent == "Response B")
    }

    @Test("Switches between variants")
    func switchVariant() {
        var tree = ConversationTree(systemPrompt: "System")
        tree.append(.user("Hello"))
        tree.append(.assistant("Response A"))
        let parentId = tree.activeLeafParentId()!
        tree.addVariant(parentId: parentId, message: .assistant("Response B"))
        tree.switchVariant(parentId: parentId, index: 0)
        #expect(tree.activeMessages().last?.textContent == "Response A")
    }

    @Test("JSON roundtrips correctly")
    func jsonRoundtrip() throws {
        var tree = ConversationTree(systemPrompt: "System")
        tree.append(.user("Hello"))
        tree.append(.assistant("Hi"))
        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(ConversationTree.self, from: data)
        #expect(decoded.activeMessages().count == 3)
    }
}
