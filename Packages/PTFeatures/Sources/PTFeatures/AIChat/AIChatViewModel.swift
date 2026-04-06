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
    }
}
