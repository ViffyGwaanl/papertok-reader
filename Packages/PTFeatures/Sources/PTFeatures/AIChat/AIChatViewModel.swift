import Foundation
import Observation

@MainActor @Observable
public final class AIChatViewModel {
    public var conversationTree: ConversationTree
    public var isStreaming: Bool = false
    public var currentStreamText: String = ""
    public var errorMessage: String?

    public init(systemPrompt: String = "You are a helpful reading assistant.") {
        self.conversationTree = ConversationTree(systemPrompt: systemPrompt)
    }

    /// Messages in the active conversation branch.
    public var messages: [ChatMessage] {
        conversationTree.activeMessages()
    }

    /// Send a user message (actual streaming handled by provider in Phase 7).
    public func sendMessage(_ text: String) {
        conversationTree.append(.user(text))
        // Streaming implementation deferred to Phase 7 (needs ChatModelProvider instance)
    }

    /// Add an assistant response (used after streaming completes).
    public func addAssistantMessage(_ text: String) {
        conversationTree.append(.assistant(text))
    }

    /// Clear conversation and start fresh.
    public func clearConversation(systemPrompt: String = "You are a helpful reading assistant.") {
        conversationTree = ConversationTree(systemPrompt: systemPrompt)
        currentStreamText = ""
        errorMessage = nil
        streamingTokens.removeAll()
        pendingApprovals.removeAll()
        attachments.removeAll()
    }

    // MARK: - Attachment Support

    public struct Attachment: Sendable, Identifiable {
        public enum AttachmentType: Sendable { case image, file }
        public let id = UUID()
        public let type: AttachmentType
        public let name: String
        public let data: Data
        public init(type: AttachmentType, name: String, data: Data) {
            self.type = type; self.name = name; self.data = data
        }
    }

    public var attachments: [Attachment] = []

    public func addAttachment(_ attachment: Attachment) {
        attachments.append(attachment)
    }

    public func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    public func clearAttachments() {
        attachments.removeAll()
    }

    // MARK: - Provider Selection

    public var selectedProviderId: String = ""
    public var selectedModelId: String = ""

    // MARK: - Streaming Tokens

    public var streamingTokens: [String] = []

    public func appendStreamToken(_ token: String) {
        streamingTokens.append(token)
        currentStreamText += token
    }

    public func finalizeStream() {
        let text = currentStreamText
        addAssistantMessage(text)
        currentStreamText = ""
        streamingTokens.removeAll()
        isStreaming = false
    }

    // MARK: - Tool Approval Queue

    public struct PendingToolApproval: Sendable, Identifiable {
        public let id = UUID()
        public let toolName: String
        public let toolCallId: String
        public let arguments: String
        public var isApproved: Bool? = nil
    }

    public var pendingApprovals: [PendingToolApproval] = []

    public func requestApproval(toolName: String, toolCallId: String, arguments: String) {
        pendingApprovals.append(PendingToolApproval(toolName: toolName, toolCallId: toolCallId, arguments: arguments))
    }

    public func resolveApproval(id: UUID, approved: Bool) {
        if let idx = pendingApprovals.firstIndex(where: { $0.id == id }) {
            pendingApprovals[idx].isApproved = approved
        }
    }
}
