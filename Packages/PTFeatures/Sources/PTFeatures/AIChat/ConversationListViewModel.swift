import Foundation
import Observation
import PTAIServices
import PTCore

public struct ConversationListItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
    public let isPinned: Bool
    public let bookId: String?
    public let snippet: String
    public let messageCount: Int
}

public enum ConversationBookFilter: Hashable, Sendable {
    case all
    case global
    case book(id: String)
}

public enum ConversationListSortMode: String, Hashable, Sendable, CaseIterable, Codable {
    case lastUsed
    case created
    case title
}

public enum ConversationExportFormat: String, Hashable, Sendable, CaseIterable, Codable {
    case markdown
    case json
}

public enum ConversationListError: LocalizedError, Equatable {
    case emptyTitle
    case persistenceFailed(String)
    case exportFailed(String)
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return String(localized: "chat.conversations.rename.error_empty")
        case .persistenceFailed(let detail):
            return detail
        case .exportFailed(let detail):
            return detail
        case .notFound(let id):
            let message = String(localized: "chat.conversations.rename.error_empty")
            return "\(message) [\(id)]"
        }
    }
}

@MainActor
@Observable
public final class ConversationListViewModel {
    public private(set) var conversations: [ConversationListItem] = []
    public private(set) var rawItems: [ConversationListItem] = []
    public var searchQuery: String = ""
    public var bookFilter: ConversationBookFilter = .all
    public var pinnedFirst: Bool = true
    public var sortMode: ConversationListSortMode = .lastUsed
    public var isLoading: Bool = false
    public private(set) var errorMessage: String?

    private let persistence: ConversationPersistenceService
    private let chatViewModel: AIChatViewModel

    public init(persistence: ConversationPersistenceService, chatViewModel: AIChatViewModel) {
        self.persistence = persistence
        self.chatViewModel = chatViewModel
    }

    // MARK: - Refresh

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let summaries = try persistence.listSummaries()
            rawItems = summaries.map { s in
                // listSummaries doesn't carry createdAt; load full record only when required.
                // For ordering by .created we need createdAt — load full records lazily.
                ConversationListItem(
                    id: s.id,
                    title: s.title,
                    createdAt: s.updatedAt,
                    updatedAt: s.updatedAt,
                    isPinned: s.isPinned,
                    bookId: s.bookId,
                    snippet: s.lastMessagePreview,
                    messageCount: s.messageCount
                )
            }
            // Enrich with actual createdAt from persisted files.
            var enriched: [ConversationListItem] = []
            enriched.reserveCapacity(rawItems.count)
            for item in rawItems {
                if let full = try? persistence.load(id: item.id) {
                    enriched.append(
                        ConversationListItem(
                            id: item.id,
                            title: item.title,
                            createdAt: full.createdAt,
                            updatedAt: full.updatedAt,
                            isPinned: full.isPinned,
                            bookId: full.bookId,
                            snippet: String(item.snippet.prefix(80)),
                            messageCount: item.messageCount
                        )
                    )
                } else {
                    enriched.append(item)
                }
            }
            rawItems = enriched
            applyFiltering()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "common.failed_to_load")
            rawItems = []
            conversations = []
        }
    }

    // MARK: - Setters

    public func setBookFilter(_ filter: ConversationBookFilter) {
        bookFilter = filter
        applyFiltering()
    }

    public func setSearchQuery(_ query: String) {
        searchQuery = query
        applyFiltering()
    }

    public func setSortMode(_ mode: ConversationListSortMode) {
        sortMode = mode
        applyFiltering()
    }

    // MARK: - Filter + Sort

    private func applyFiltering() {
        var items = rawItems

        switch bookFilter {
        case .all:
            break
        case .global:
            items = items.filter { $0.bookId == nil }
        case .book(let id):
            items = items.filter { $0.bookId == id }
        }

        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty == false {
            let needle = trimmedQuery.lowercased()
            items = items.filter {
                $0.title.lowercased().contains(needle) ||
                $0.snippet.lowercased().contains(needle)
            }
        }

        let sorted: [ConversationListItem]
        if pinnedFirst {
            let pinned = items.filter { $0.isPinned }
            let rest = items.filter { !$0.isPinned }
            sorted = sortItems(pinned) + sortItems(rest)
        } else {
            sorted = sortItems(items)
        }

        conversations = sorted
    }

    private func sortItems(_ items: [ConversationListItem]) -> [ConversationListItem] {
        switch sortMode {
        case .lastUsed:
            return items.sorted { $0.updatedAt > $1.updatedAt }
        case .created:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    // MARK: - Mutations

    public func rename(id: String, to newTitle: String) async throws {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw ConversationListError.emptyTitle }
        do {
            guard var loaded = try persistence.load(id: id) else {
                throw ConversationListError.notFound(id)
            }
            loaded.title = trimmed
            loaded.updatedAt = Date()
            try persistence.save(loaded)
        } catch let error as ConversationListError {
            throw error
        } catch {
            throw ConversationListError.persistenceFailed(error.localizedDescription)
        }
        await refresh()
    }

    public func delete(id: String) async throws {
        do {
            try persistence.delete(id: id)
        } catch {
            throw ConversationListError.persistenceFailed(error.localizedDescription)
        }
        if chatViewModel.conversationId == id {
            // Fall back to most recent remaining, or start fresh.
            if let next = (try? persistence.listSummaries())?.first {
                _ = chatViewModel.loadConversation(id: next.id)
            } else {
                chatViewModel.clearConversation()
            }
        }
        await refresh()
    }

    public func togglePin(id: String) async throws {
        do {
            guard var loaded = try persistence.load(id: id) else {
                throw ConversationListError.notFound(id)
            }
            loaded.isPinned.toggle()
            try persistence.save(loaded)
        } catch let error as ConversationListError {
            throw error
        } catch {
            throw ConversationListError.persistenceFailed(error.localizedDescription)
        }
        await refresh()
    }

    // MARK: - Export

    public func export(id: String, format: ConversationExportFormat) async throws -> URL {
        let conversation: ConversationPersistenceService.PersistedConversation
        do {
            guard let loaded = try persistence.load(id: id) else {
                throw ConversationListError.notFound(id)
            }
            conversation = loaded
        } catch let error as ConversationListError {
            throw error
        } catch {
            throw ConversationListError.exportFailed(error.localizedDescription)
        }

        let ext = format == .markdown ? "md" : "json"
        let safe = Self.safeFilename(for: conversation.title, fallbackId: conversation.id)
        let dir = try Self.exportDirectory()
        let url = dir.appendingPathComponent("\(safe).\(ext)")

        do {
            switch format {
            case .markdown:
                let md = Self.renderMarkdown(conversation)
                try md.write(to: url, atomically: true, encoding: .utf8)
            case .json:
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(conversation)
                try data.write(to: url, options: .atomic)
            }
        } catch {
            throw ConversationListError.exportFailed(error.localizedDescription)
        }
        return url
    }

    private static func exportDirectory() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("PaperTok", isDirectory: true)
            .appendingPathComponent("Exports", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func safeFilename(for title: String, fallbackId: String) -> String {
        var scalars: [Character] = []
        for ch in title {
            if ch.isASCII {
                if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" {
                    scalars.append(ch)
                } else {
                    scalars.append("_")
                }
                continue
            }
            // Preserve CJK Unified Ideographs (U+4E00..U+9FFF).
            if let scalar = ch.unicodeScalars.first,
               (0x4E00...0x9FFF).contains(scalar.value) {
                scalars.append(ch)
            } else {
                scalars.append("_")
            }
        }
        var result = String(scalars)
        if result.count > 100 {
            result = String(result.prefix(100))
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if trimmed.isEmpty {
            let prefix = String(fallbackId.prefix(8))
            let fallback = Self.fallbackFilenamePrefix + prefix
            return fallback
        }
        return result
    }

    private static let fallbackFilenamePrefix = "conversation_"

    private static func renderMarkdown(_ c: ConversationPersistenceService.PersistedConversation) -> String {
        var md = "# \(c.title)\n\n"
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let messages = c.tree.activeMessages().filter { $0.role != .system }
        md += "_Created \(isoFormatter.string(from: c.createdAt)) \u{00B7} \(messages.count) messages_\n\n"
        md += "---\n\n"
        for msg in messages {
            guard let text = msg.textContent, text.isEmpty == false else { continue }
            let heading: String
            switch msg.role {
            case .user: heading = "User"
            case .assistant: heading = "Assistant"
            case .tool: heading = "Tool"
            case .system: continue
            }
            md += "## \(heading)\n\n\(text)\n\n"
        }
        return md
    }
}
