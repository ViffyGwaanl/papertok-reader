import Foundation

/// Persists and loads AI chat conversations as JSON files on disk.
///
/// Each conversation is stored as `{id}.json` inside the conversations directory.
/// The service provides CRUD operations and a lightweight metadata summary for listing.
public struct ConversationPersistenceService: Sendable {
    private let directory: URL
    private let userDefaults: UserDefaults

    /// Legacy UserDefaults key previously written by `ConversationListView` to persist pinned ids.
    public static let legacyPinnedConversationsKey = "papertok.ai.pinnedConversations"
    /// Idempotency marker: prevents the legacy pin migration from ever re-running.
    public static let legacyPinnedMigrationMarkerKey = "papertok.ai.pinnedConversations.migrated_v2"

    public init(directory: URL, userDefaults: UserDefaults = .standard) {
        self.directory = directory
        self.userDefaults = userDefaults
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
        public var isPinned: Bool
        public var bookId: String?

        public init(
            id: String = UUID().uuidString,
            title: String,
            systemPrompt: String,
            tree: ConversationTree,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            providerId: String? = nil,
            modelId: String? = nil,
            isPinned: Bool = false,
            bookId: String? = nil
        ) {
            self.id = id
            self.title = title
            self.systemPrompt = systemPrompt
            self.tree = tree
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.providerId = providerId
            self.modelId = modelId
            self.isPinned = isPinned
            self.bookId = bookId
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, systemPrompt, tree, createdAt, updatedAt, providerId, modelId, isPinned, bookId
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
            self.title = try container.decode(String.self, forKey: .title)
            self.systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
            self.tree = try container.decode(ConversationTree.self, forKey: .tree)
            self.createdAt = try container.decode(Date.self, forKey: .createdAt)
            self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
            self.providerId = try container.decodeIfPresent(String.self, forKey: .providerId)
            self.modelId = try container.decodeIfPresent(String.self, forKey: .modelId)
            // decodeIfPresent keeps pre-W2.1a JSON files on disk loadable: missing keys default.
            self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
            self.bookId = try container.decodeIfPresent(String.self, forKey: .bookId)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encode(systemPrompt, forKey: .systemPrompt)
            try container.encode(tree, forKey: .tree)
            try container.encode(createdAt, forKey: .createdAt)
            try container.encode(updatedAt, forKey: .updatedAt)
            try container.encodeIfPresent(providerId, forKey: .providerId)
            try container.encodeIfPresent(modelId, forKey: .modelId)
            try container.encode(isPinned, forKey: .isPinned)
            try container.encodeIfPresent(bookId, forKey: .bookId)
        }
    }

    /// Lightweight summary for list views.
    public struct ConversationSummary: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let updatedAt: Date
        public let messageCount: Int
        public let lastMessagePreview: String
        public let isPinned: Bool
        public let bookId: String?
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
        migrateLegacyPinnedConversations()
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
                lastMessagePreview: preview,
                isPinned: conversation.isPinned,
                bookId: conversation.bookId
            ))
        }

        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Legacy Pin Migration

    /// One-shot migration: moves pinned conversation ids from the legacy UserDefaults array
    /// into the persisted conversations' `isPinned` field. Guarded by an idempotency marker so
    /// subsequent `listSummaries()` calls do not re-touch disk or UserDefaults.
    private func migrateLegacyPinnedConversations() {
        guard userDefaults.bool(forKey: Self.legacyPinnedMigrationMarkerKey) == false else { return }

        if let ids = userDefaults.array(forKey: Self.legacyPinnedConversationsKey) as? [String] {
            for id in ids {
                guard var existing = try? load(id: id) else { continue }
                if existing.isPinned == false {
                    existing.isPinned = true
                    try? save(existing)
                }
            }
        }

        userDefaults.removeObject(forKey: Self.legacyPinnedConversationsKey)
        userDefaults.set(true, forKey: Self.legacyPinnedMigrationMarkerKey)
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
