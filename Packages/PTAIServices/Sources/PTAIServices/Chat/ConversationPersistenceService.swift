import Foundation

/// Persists and loads AI chat conversations as JSON files on disk.
///
/// Each conversation is stored as `{id}.json` inside the conversations directory.
/// The service provides CRUD operations and a lightweight metadata summary for listing.
public struct ConversationPersistenceService: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Create the conversations directory if it does not exist.
    public func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Persisted Model

    public struct PersistedConversation: Codable, Sendable, Identifiable {
        public let id: String
        public var title: String
        public var systemPrompt: String
        public var tree: ConversationTree
        public let createdAt: Date
        public var updatedAt: Date
        public var providerId: String?
        public var modelId: String?

        public init(
            id: String = UUID().uuidString,
            title: String,
            systemPrompt: String,
            tree: ConversationTree,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            providerId: String? = nil,
            modelId: String? = nil
        ) {
            self.id = id
            self.title = title
            self.systemPrompt = systemPrompt
            self.tree = tree
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.providerId = providerId
            self.modelId = modelId
        }
    }

    /// Lightweight summary for list views.
    public struct ConversationSummary: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let updatedAt: Date
        public let messageCount: Int
        public let lastMessagePreview: String
    }

    // MARK: - Save

    public func save(_ conversation: PersistedConversation) throws {
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(conversation)
        let fileURL = directory.appendingPathComponent("\(conversation.id).json")
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Load

    public func load(id: String) throws -> PersistedConversation? {
        let fileURL = directory.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PersistedConversation.self, from: data)
    }

    // MARK: - List

    public func listSummaries() throws -> [ConversationSummary] {
        try ensureDirectory()
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var summaries: [ConversationSummary] = []
        for fileURL in contents where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let conversation = try? decoder.decode(PersistedConversation.self, from: data) else {
                continue
            }
            let messages = conversation.tree.activeMessages()
            let lastText = messages.last(where: { $0.role == .assistant || $0.role == .user })?.textContent ?? ""
            let preview = String(lastText.prefix(120))
            summaries.append(ConversationSummary(
                id: conversation.id,
                title: conversation.title,
                updatedAt: conversation.updatedAt,
                messageCount: messages.count,
                lastMessagePreview: preview
            ))
        }

        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Delete

    public func delete(id: String) throws {
        let fileURL = directory.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Delete All

    public func deleteAll() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for fileURL in contents where fileURL.pathExtension == "json" {
            try fm.removeItem(at: fileURL)
        }
    }
}
