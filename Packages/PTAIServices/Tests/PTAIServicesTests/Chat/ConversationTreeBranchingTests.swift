import Testing
import Foundation
@testable import PTAIServices

@Suite("ConversationTreeBranching")
struct ConversationTreeBranchingTests {
    private func seededTree() -> (ConversationTree, String, String) {
        var tree = ConversationTree(systemPrompt: "System")
        tree.append(.user("Original question"))
        let userId = tree.activeLeafId()
        tree.append(.assistant("Original answer"))
        let assistantId = tree.activeLeafId()
        return (tree, userId, assistantId)
    }

    @Test("editUserMessage creates sibling branch at the user's parent")
    func editUserMessageCreatesSiblingBranch() {
        var (tree, userId, _) = seededTree()
        let parentId = tree.nodes[userId]!.parentId!
        _ = tree.editUserMessage(userId, newText: "Revised question")
        #expect(tree.variantCount(parentId: parentId) == 2)
    }

    @Test("editUserMessage activates the new branch")
    func editUserMessageActivatesNewBranch() {
        var (tree, userId, _) = seededTree()
        let newId = tree.editUserMessage(userId, newText: "Revised question")
        #expect(newId != nil)
        let active = tree.activeMessages()
        #expect(active.last?.role == .user)
        #expect(active.last?.textContent == "Revised question")
    }

    @Test("editUserMessage preserves the original branch")
    func editUserMessagePreservesOriginalBranch() {
        var (tree, userId, _) = seededTree()
        _ = tree.editUserMessage(userId, newText: "Revised question")
        #expect(tree.nodes[userId] != nil)
        #expect(tree.nodes[userId]?.message.textContent == "Original question")
    }

    @Test("editUserMessage returns nil for unknown id")
    func editUserMessageReturnsNilForUnknownId() {
        var (tree, _, _) = seededTree()
        let result = tree.editUserMessage("nonexistent-id", newText: "anything")
        #expect(result == nil)
    }

    @Test("retryAssistantMessage creates sibling branch under the user turn")
    func retryAssistantMessageCreatesSiblingBranch() {
        var (tree, userId, assistantId) = seededTree()
        let newId = tree.retryAssistantMessage(assistantId)
        #expect(newId != nil)
        #expect(tree.variantCount(parentId: userId) == 2)
    }

    @Test("branchSiblings returns all children of parent")
    func branchSiblingsReturnsAllChildrenOfParent() {
        var (tree, userId, assistantId) = seededTree()
        tree.addVariant(parentId: userId, message: .assistant("Alt B"))
        tree.addVariant(parentId: userId, message: .assistant("Alt C"))
        let siblings = tree.branchSiblings(of: assistantId)
        #expect(siblings.count == 3)
        #expect(siblings.contains(assistantId))
    }

    @Test("switchToBranch updates active path to include node")
    func switchToBranchUpdatesActivePath() {
        var (tree, userId, assistantId) = seededTree()
        tree.addVariant(parentId: userId, message: .assistant("Alt B"))
        // After addVariant, active is Alt B. Switch back to original.
        tree.switchToBranch(assistantId)
        #expect(tree.activeMessages().last?.textContent == "Original answer")
    }
}
