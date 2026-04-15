import Testing
import Foundation
@testable import PTFeatures
import PTAIServices
import PTCore

@Suite("AIChatViewModel Message Ops (W2.2c)")
struct AIChatViewModelMessageOpsTests {
    final class StubState: @unchecked Sendable {
        private let lock = NSLock()
        private var _nextChunks: [String] = []
        private var _invocations = 0

        var nextChunks: [String] {
            get { lock.lock(); defer { lock.unlock() }; return _nextChunks }
            set { lock.lock(); _nextChunks = newValue; lock.unlock() }
        }
        var invocations: Int {
            get { lock.lock(); defer { lock.unlock() }; return _invocations }
        }

        func recordInvocation() {
            lock.lock(); _invocations += 1; lock.unlock()
        }
    }

    struct StubProvider: ChatModelProvider {
        let id: String = "stub-ops"
        let displayName: String = "Stub Ops Provider"
        let supportedCapabilities: Set<ModelCapability> = [.chat, .streaming]
        let state: StubState

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(message: .assistant("unused"))
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            let state = self.state
            return AsyncThrowingStream { continuation in
                state.recordInvocation()
                for chunk in state.nextChunks {
                    continuation.yield(ChatStreamChunk(delta: .text(chunk)))
                }
                continuation.finish()
            }
        }
    }

    private static func makeRuntime(state: StubState) -> AIChatViewModel.Runtime {
        AIChatViewModel.Runtime(
            providers: [
                .init(
                    id: "stub",
                    displayName: "Stub",
                    models: [
                        .init(id: "stub-model", displayName: "Stub", supportsThinking: false, supportsVision: false)
                    ],
                    makeProvider: { StubProvider(state: state) }
                )
            ]
        )
    }

    private static func isolatedDefaults() -> UserDefaults {
        let name = "AIChatViewModelMessageOpsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @MainActor
    private static func makeVM(state: StubState) -> AIChatViewModel {
        AIChatViewModel(runtime: makeRuntime(state: state), defaults: isolatedDefaults())
    }

    @MainActor
    private static func nodeId(_ vm: AIChatViewModel, forMessageId messageId: String) -> String? {
        vm.conversationTree.nodes.first(where: { $0.value.message.id == messageId })?.key
    }

    @MainActor
    @Test("editAndResend creates a new user branch and triggers generation")
    func editAndResendCreatesNewBranchAndTriggersGeneration() async {
        let state = StubState()
        state.nextChunks = ["first"]
        let vm = Self.makeVM(state: state)

        _ = await vm.sendMessage("original question")
        let originalUserMsg = vm.messages.first(where: { $0.role == .user })!
        let originalUserNodeId = Self.nodeId(vm, forMessageId: originalUserMsg.id)!
        #expect(state.invocations == 1)

        state.nextChunks = ["edited response"]
        await vm.editAndResend(messageId: originalUserMsg.id, newText: "edited")

        // Siblings of the original user message now include the new one.
        let siblings = vm.conversationTree.branchSiblings(of: originalUserNodeId)
        #expect(siblings.count == 2)
        // Active user message text is the edited value.
        let activeUser = vm.messages.first(where: { $0.role == .user })?.textContent
        #expect(activeUser == "edited")
        // Provider was invoked a second time.
        #expect(state.invocations == 2)
        let activeAssistant = vm.messages.last(where: { $0.role == .assistant })?.textContent
        #expect(activeAssistant == "edited response")
    }

    @MainActor
    @Test("retry preserves old assistant branch and replaces active content")
    func retryReplacesAssistantContentInPlace() async {
        let state = StubState()
        state.nextChunks = ["first"]
        let vm = Self.makeVM(state: state)

        _ = await vm.sendMessage("hello")
        let originalAssistant = vm.messages.last(where: { $0.role == .assistant })!
        let originalAssistantNodeId = Self.nodeId(vm, forMessageId: originalAssistant.id)!
        #expect(originalAssistant.textContent == "first")

        state.nextChunks = ["second"]
        await vm.retry(messageId: originalAssistant.id)

        // Active assistant message is the new "second" response.
        let activeAssistant = vm.messages.last(where: { $0.role == .assistant })?.textContent
        #expect(activeAssistant == "second")
        // Old branch still exists in the tree as a sibling.
        let siblings = vm.conversationTree.branchSiblings(of: originalAssistantNodeId)
        #expect(siblings.count == 2)
        #expect(siblings.contains(originalAssistantNodeId))
    }

    @MainActor
    @Test("regenerateLastAssistant preserves the old branch (bug fix)")
    func regenerateLastAssistantPreservesOldBranch() async {
        let state = StubState()
        state.nextChunks = ["alpha"]
        let vm = Self.makeVM(state: state)

        _ = await vm.sendMessage("hi")
        let original = vm.messages.last(where: { $0.role == .assistant })!
        let originalNodeId = Self.nodeId(vm, forMessageId: original.id)!

        state.nextChunks = ["beta"]
        await vm.regenerateLastAssistant()

        let activeText = vm.messages.last(where: { $0.role == .assistant })?.textContent
        #expect(activeText == "beta")
        let siblings = vm.conversationTree.branchSiblings(of: originalNodeId)
        #expect(siblings.count == 2)
        // Bug fix: old node still lives in the tree.
        #expect(vm.conversationTree.nodes[originalNodeId] != nil)
    }

    @MainActor
    @Test("switchToBranch updates the active message path")
    func switchToBranchUpdatesActiveMessages() async {
        let state = StubState()
        state.nextChunks = ["alpha"]
        let vm = Self.makeVM(state: state)
        _ = await vm.sendMessage("hi")
        let firstMsg = vm.messages.last(where: { $0.role == .assistant })!
        let firstNodeId = Self.nodeId(vm, forMessageId: firstMsg.id)!

        state.nextChunks = ["beta"]
        await vm.regenerateLastAssistant()
        #expect(vm.messages.last(where: { $0.role == .assistant })?.textContent == "beta")

        vm.switchToBranch(firstNodeId)
        #expect(vm.messages.last(where: { $0.role == .assistant })?.textContent == "alpha")
    }

    @MainActor
    @Test("branchNavigatorState reports 1-based index and total siblings")
    func branchNavigatorComputesIndexAndTotal() async {
        let state = StubState()
        state.nextChunks = ["alpha"]
        let vm = Self.makeVM(state: state)
        _ = await vm.sendMessage("hi")
        let firstMsg = vm.messages.last(where: { $0.role == .assistant })!
        let firstId = Self.nodeId(vm, forMessageId: firstMsg.id)!

        state.nextChunks = ["beta"]
        await vm.regenerateLastAssistant()
        let secondMsg = vm.messages.last(where: { $0.role == .assistant })!

        state.nextChunks = ["gamma"]
        await vm.retry(messageId: secondMsg.id)
        let thirdMsg = vm.messages.last(where: { $0.role == .assistant })!
        let thirdId = Self.nodeId(vm, forMessageId: thirdMsg.id)!

        // Three siblings total; the active (third) is the latest.
        let stateThird = vm.branchNavigatorState(for: thirdMsg.id)
        #expect(stateThird?.total == 3)
        #expect(stateThird?.index == 3)
        let stateFirst = vm.branchNavigatorState(for: firstMsg.id)
        #expect(stateFirst?.total == 3)
        #expect(stateFirst?.index == 1)
        _ = firstId
        _ = thirdId
    }
}
