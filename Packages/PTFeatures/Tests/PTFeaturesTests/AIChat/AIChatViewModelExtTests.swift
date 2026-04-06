import Testing
import Foundation
@testable import PTFeatures

@Suite("AIChatViewModel Extensions")
struct AIChatViewModelExtTests {

    @MainActor
    @Test("attachments initially empty")
    func attachmentsInitiallyEmpty() {
        let vm = AIChatViewModel()
        #expect(vm.attachments.isEmpty)
    }

    @MainActor
    @Test("addAttachment increases count")
    func addAttachment() {
        let vm = AIChatViewModel()
        vm.addAttachment(.init(type: .image, name: "photo.jpg", data: Data()))
        #expect(vm.attachments.count == 1)
    }

    @MainActor
    @Test("clearAttachments empties list")
    func clearAttachments() {
        let vm = AIChatViewModel()
        vm.addAttachment(.init(type: .image, name: "photo.jpg", data: Data()))
        vm.clearAttachments()
        #expect(vm.attachments.isEmpty)
    }

    @MainActor
    @Test("removeAttachment removes specific item")
    func removeAttachment() {
        let vm = AIChatViewModel()
        vm.addAttachment(.init(type: .image, name: "a.jpg", data: Data()))
        vm.addAttachment(.init(type: .file, name: "b.pdf", data: Data()))
        let idToRemove = vm.attachments[0].id
        vm.removeAttachment(id: idToRemove)
        #expect(vm.attachments.count == 1)
        #expect(vm.attachments[0].name == "b.pdf")
    }

    @MainActor
    @Test("selectedProviderId defaults to empty")
    func selectedProviderDefault() {
        let vm = AIChatViewModel()
        #expect(vm.selectedProviderId.isEmpty)
        #expect(vm.selectedModelId.isEmpty)
    }

    @MainActor
    @Test("appendStreamToken accumulates text")
    func streamTokenAccumulation() {
        let vm = AIChatViewModel()
        vm.appendStreamToken("Hello")
        vm.appendStreamToken(" world")
        #expect(vm.currentStreamText == "Hello world")
        #expect(vm.streamingTokens.count == 2)
    }

    @MainActor
    @Test("finalizeStream creates assistant message and resets")
    func finalizeStream() {
        let vm = AIChatViewModel()
        vm.isStreaming = true
        vm.appendStreamToken("Response text")
        vm.finalizeStream()
        #expect(vm.currentStreamText.isEmpty)
        #expect(vm.streamingTokens.isEmpty)
        #expect(vm.isStreaming == false)
        // The assistant message should be in the conversation tree
        let messages = vm.messages
        let assistantMessages = messages.filter { $0.role == .assistant }
        #expect(assistantMessages.count == 1)
        #expect(assistantMessages.first?.textContent == "Response text")
    }

    @MainActor
    @Test("requestApproval adds to pending list")
    func toolApproval() {
        let vm = AIChatViewModel()
        vm.requestApproval(toolName: "calendar_write", toolCallId: "tc1", arguments: "{}")
        #expect(vm.pendingApprovals.count == 1)
        #expect(vm.pendingApprovals[0].toolName == "calendar_write")
        #expect(vm.pendingApprovals[0].isApproved == nil)
    }

    @MainActor
    @Test("resolveApproval updates status")
    func resolveApproval() {
        let vm = AIChatViewModel()
        vm.requestApproval(toolName: "test", toolCallId: "tc1", arguments: "{}")
        let id = vm.pendingApprovals[0].id
        vm.resolveApproval(id: id, approved: true)
        #expect(vm.pendingApprovals[0].isApproved == true)
    }

    @MainActor
    @Test("clearConversation resets all state")
    func clearConversation() {
        let vm = AIChatViewModel()
        vm.addAttachment(.init(type: .image, name: "test.jpg", data: Data()))
        vm.appendStreamToken("test")
        vm.requestApproval(toolName: "test", toolCallId: "tc1", arguments: "{}")
        vm.clearConversation()
        #expect(vm.attachments.isEmpty)
        #expect(vm.currentStreamText.isEmpty)
        #expect(vm.streamingTokens.isEmpty)
        #expect(vm.pendingApprovals.isEmpty)
    }
}
