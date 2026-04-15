import Foundation

public struct ConversationTree: Codable, Sendable {
    public var rootId: String
    public var nodes: [String: ConversationNode]

    public struct ConversationNode: Codable, Sendable {
        public let id: String
        public let role: ChatRole
        public let message: ChatMessage
        public let parentId: String?
        public var childIds: [String]
        public var activeChildIndex: Int
        public let createdAt: Date

        public init(id: String = UUID().uuidString, message: ChatMessage, parentId: String?, createdAt: Date = Date()) {
            self.id = id; self.role = message.role; self.message = message; self.parentId = parentId
            self.childIds = []; self.activeChildIndex = 0; self.createdAt = createdAt
        }
    }

    public init(systemPrompt: String) {
        let rootMessage = ChatMessage.system(systemPrompt)
        let rootNode = ConversationNode(message: rootMessage, parentId: nil)
        self.rootId = rootNode.id; self.nodes = [rootNode.id: rootNode]
    }

    public func activeMessages() -> [ChatMessage] {
        var messages: [ChatMessage] = []; var currentId: String? = rootId
        while let id = currentId, let node = nodes[id] {
            messages.append(node.message)
            if node.childIds.isEmpty { break }
            let idx = min(node.activeChildIndex, node.childIds.count - 1)
            currentId = node.childIds[idx]
        }
        return messages
    }

    public func activeLeafId() -> String {
        var currentId = rootId
        while let node = nodes[currentId], !node.childIds.isEmpty {
            let idx = min(node.activeChildIndex, node.childIds.count - 1)
            currentId = node.childIds[idx]
        }
        return currentId
    }

    public func activeLeafParentId() -> String? { nodes[activeLeafId()]?.parentId }

    public mutating func append(_ message: ChatMessage) {
        let leafId = activeLeafId()
        let newNode = ConversationNode(message: message, parentId: leafId)
        nodes[newNode.id] = newNode
        nodes[leafId]?.childIds.append(newNode.id)
        if let count = nodes[leafId]?.childIds.count {
            nodes[leafId]?.activeChildIndex = count - 1
        }
    }

    public mutating func addVariant(parentId: String, message: ChatMessage) {
        let newNode = ConversationNode(message: message, parentId: parentId)
        nodes[newNode.id] = newNode
        nodes[parentId]?.childIds.append(newNode.id)
        if let count = nodes[parentId]?.childIds.count {
            nodes[parentId]?.activeChildIndex = count - 1
        }
    }

    public mutating func switchVariant(parentId: String, index: Int) {
        guard let node = nodes[parentId], index < node.childIds.count else { return }
        nodes[parentId]?.activeChildIndex = index
    }

    public func variantCount(parentId: String) -> Int { nodes[parentId]?.childIds.count ?? 0 }

    @discardableResult
    public mutating func editUserMessage(_ messageId: String, newText: String) -> String? {
        guard let node = nodes[messageId], node.role == .user, let parentId = node.parentId else { return nil }
        let newNode = ConversationNode(message: .user(newText), parentId: parentId)
        nodes[newNode.id] = newNode
        nodes[parentId]?.childIds.append(newNode.id)
        if let count = nodes[parentId]?.childIds.count {
            nodes[parentId]?.activeChildIndex = count - 1
        }
        return newNode.id
    }

    @discardableResult
    public mutating func retryAssistantMessage(_ messageId: String) -> String? {
        guard let node = nodes[messageId], node.role == .assistant, let parentId = node.parentId else { return nil }
        let newNode = ConversationNode(message: .assistant(""), parentId: parentId)
        nodes[newNode.id] = newNode
        nodes[parentId]?.childIds.append(newNode.id)
        if let count = nodes[parentId]?.childIds.count {
            nodes[parentId]?.activeChildIndex = count - 1
        }
        return newNode.id
    }

    public func branchSiblings(of nodeId: String) -> [String] {
        guard let node = nodes[nodeId] else { return [] }
        guard let parentId = node.parentId, let parent = nodes[parentId] else { return [nodeId] }
        return parent.childIds
    }

    public mutating func switchToBranch(_ nodeId: String) {
        guard nodes[nodeId] != nil else { return }
        var currentId = nodeId
        while let node = nodes[currentId], let parentId = node.parentId, let parent = nodes[parentId] {
            if let idx = parent.childIds.firstIndex(of: currentId) {
                nodes[parentId]?.activeChildIndex = idx
            }
            currentId = parentId
        }
    }
}
