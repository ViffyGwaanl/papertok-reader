import Testing
@testable import PTFeatures
import PTAIServices

@Suite("BranchNavigatorView")
struct BranchNavigatorViewTests {

    @MainActor
    @Test("single variant yields count of 1")
    func singleVariantCount() {
        let vm = AIChatViewModel()
        vm.conversationTree.append(.user("Hello"))
        // rootId has one child (the user message)
        let variants = vm.conversationTree.variantCount(parentId: vm.conversationTree.rootId)
        #expect(variants == 1)
    }

    @MainActor
    @Test("multiple variants increase count")
    func multipleVariants() {
        let vm = AIChatViewModel()
        vm.conversationTree.append(.user("Hello"))
        // Add a variant sibling to the user message under the same root parent
        vm.conversationTree.addVariant(
            parentId: vm.conversationTree.rootId,
            message: .user("Hi there")
        )
        let variants = vm.conversationTree.variantCount(parentId: vm.conversationTree.rootId)
        #expect(variants == 2)
    }

    @MainActor
    @Test("switchVariant changes active branch")
    func switchVariant() {
        let vm = AIChatViewModel()
        vm.conversationTree.append(.user("Hello"))
        vm.conversationTree.addVariant(
            parentId: vm.conversationTree.rootId,
            message: .user("Hi there")
        )
        // Initially active is the last added (index 1)
        let messagesBeforeSwitch = vm.messages
        let lastUser = messagesBeforeSwitch.last
        #expect(lastUser?.textContent == "Hi there")

        // Switch to first variant
        vm.conversationTree.switchVariant(parentId: vm.conversationTree.rootId, index: 0)
        let messagesAfterSwitch = vm.messages
        let lastUserAfter = messagesAfterSwitch.last
        #expect(lastUserAfter?.textContent == "Hello")
    }
}
