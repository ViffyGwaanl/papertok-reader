import Foundation

/// Context provided to AI tools during execution.
/// Contains references to the current book, conversation, and platform services.
public struct ToolContext: Sendable {
    public let bookId: Int64?
    public let conversationId: String?
    /// Database access for book-related tools.
    public let database: (any ToolDatabaseAccess)?
    /// Memory store for memory tools.
    public let memoryDirectory: URL?
    /// Optional FTS5-backed memory index. When present, memory search tools should prefer
    /// this over linear file scans.
    public let memoryIndex: MemoryIndexDatabase?
    /// HTTP client for fetch/search tools.
    public let httpClient: (any ToolHTTPClient)?
    /// Calendar service for EventKit calendar operations (injected by App target).
    public let calendarService: (any CalendarServiceProtocol)?
    /// Reminders service for EventKit reminders operations (injected by App target).
    public let remindersService: (any RemindersServiceProtocol)?
    /// Sub-agent runtime bridge for best-effort delegated tasks.
    public let subAgentService: (any SubAgentServiceProtocol)?
    /// Shortcuts runtime bridge for launching iOS/macOS shortcuts.
    public let shortcutsService: (any ShortcutsServiceProtocol)?
    /// Shared live reader-session carrier for active-book tools.
    public let readerSessionStore: ReaderSessionContextStore?

    public init(
        bookId: Int64? = nil,
        conversationId: String? = nil,
        database: (any ToolDatabaseAccess)? = nil,
        memoryDirectory: URL? = nil,
        memoryIndex: MemoryIndexDatabase? = nil,
        httpClient: (any ToolHTTPClient)? = nil,
        calendarService: (any CalendarServiceProtocol)? = nil,
        remindersService: (any RemindersServiceProtocol)? = nil,
        subAgentService: (any SubAgentServiceProtocol)? = nil,
        shortcutsService: (any ShortcutsServiceProtocol)? = nil,
        readerSessionStore: ReaderSessionContextStore? = nil
    ) {
        self.bookId = bookId
        self.conversationId = conversationId
        self.database = database
        self.memoryDirectory = memoryDirectory
        self.memoryIndex = memoryIndex
        self.httpClient = httpClient
        self.calendarService = calendarService
        self.remindersService = remindersService
        self.subAgentService = subAgentService
        self.shortcutsService = shortcutsService
        self.readerSessionStore = readerSessionStore
    }

    public var activeBookId: Int64? {
        readerSessionSnapshot()?.bookId ?? bookId
    }

    public var activeReadingProgress: Double? {
        readerSessionSnapshot()?.readingProgress
    }

    public var currentChapterTitle: String? {
        readerSessionSnapshot()?.chapterTitle
    }

    public var currentChapterHref: String? {
        readerSessionSnapshot()?.locationHref
    }

    public var hasActiveReaderSession: Bool {
        readerSessionStore?.hasActiveReaderSession ?? false
    }

    public var hasBookContentBridge: Bool {
        readerSessionStore?.hasBookContentBridge ?? false
    }

    public func readerSessionSnapshot() -> ReaderSessionSnapshot? {
        readerSessionStore?.currentSnapshot()
    }

    public func activeReaderSession() async -> ResolvedReaderSession? {
        guard let snapshot = readerSessionSnapshot(),
              let provider = snapshot.contentBridgeProvider,
              let bridge = await provider() else {
            return nil
        }
        return ResolvedReaderSession(snapshot: snapshot, bridge: bridge)
    }

    public func bookContentBridge() async -> (any BookContentBridgeProtocol)? {
        await activeReaderSession()?.bridge
    }
}

public struct ResolvedReaderSession: Sendable {
    public let snapshot: ReaderSessionSnapshot
    public let bridge: any BookContentBridgeProtocol

    public init(snapshot: ReaderSessionSnapshot, bridge: any BookContentBridgeProtocol) {
        self.snapshot = snapshot
        self.bridge = bridge
    }
}

public struct ReaderSessionSnapshot: Sendable {
    public let bookId: Int64?
    public let readingProgress: Double?
    public let chapterTitle: String?
    public let locationHref: String?
    public let contentBridgeProvider: (@Sendable () async -> (any BookContentBridgeProtocol)?)?

    public init(
        bookId: Int64?,
        readingProgress: Double? = nil,
        chapterTitle: String? = nil,
        locationHref: String? = nil,
        contentBridgeProvider: (@Sendable () async -> (any BookContentBridgeProtocol)?)? = nil
    ) {
        self.bookId = bookId
        self.readingProgress = readingProgress
        self.chapterTitle = chapterTitle
        self.locationHref = locationHref
        self.contentBridgeProvider = contentBridgeProvider
    }
}

public final class ReaderSessionContextStore: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: ReaderSessionSnapshot?

    public init(snapshot: ReaderSessionSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public var activeBookId: Int64? {
        withLock { snapshot?.bookId }
    }

    public var readingProgress: Double? {
        withLock { snapshot?.readingProgress }
    }

    public var chapterTitle: String? {
        withLock { snapshot?.chapterTitle }
    }

    public var locationHref: String? {
        withLock { snapshot?.locationHref }
    }

    public var hasActiveReaderSession: Bool {
        withLock { snapshot != nil }
    }

    public var hasBookContentBridge: Bool {
        withLock { snapshot?.contentBridgeProvider != nil }
    }

    public func update(_ snapshot: ReaderSessionSnapshot?) {
        withLock {
            self.snapshot = snapshot
        }
    }

    public func clear() {
        update(nil)
    }

    public func currentSnapshot() -> ReaderSessionSnapshot? {
        withLock { snapshot }
    }

    public func bookContentBridge() async -> (any BookContentBridgeProtocol)? {
        let provider = withLock { snapshot?.contentBridgeProvider }
        return await provider?()
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Protocol for database operations needed by AI tools.
/// PTCore.AppDatabase conforms to this in Phase 12.
public protocol ToolDatabaseAccess: Sendable {
    func fetchBooks(query: String?, groupId: Int64?, limit: Int) async throws -> [[String: Any]]
    func fetchBookNotes(bookId: Int64?, keyword: String?, limit: Int) async throws -> [[String: Any]]
    func fetchReadingTime(bookId: Int64?, since: Date?) async throws -> [[String: Any]]
    func fetchTags() async throws -> [[String: Any]]
    func insertBookNote(_ fields: [String: Any]) async throws
    func fetchBook(id: Int64) async throws -> [String: Any]?
}

public extension ToolDatabaseAccess {
    func fetchBook(id: Int64) async throws -> [String: Any]? {
        let books = try await fetchBooks(query: nil, groupId: nil, limit: Int.max)
        return books.first { ($0["id"] as? Int64) == id }
    }
}

/// Protocol for HTTP operations needed by AI tools.
public protocol ToolHTTPClient: Sendable {
    func fetchText(url: URL, timeoutSeconds: Double) async throws -> String
}

public protocol SubAgentServiceProtocol: Sendable {
    func spawn(task: String, type: String, requestedSteps: Int?) async throws -> SubAgentSpawnResult
}

public struct SubAgentSpawnResult: Sendable {
    public let status: String
    public let summary: String
    public let agentType: String
    public let requestedSteps: Int?

    public init(status: String, summary: String, agentType: String, requestedSteps: Int? = nil) {
        self.status = status
        self.summary = summary
        self.agentType = agentType
        self.requestedSteps = requestedSteps
    }

    public var jsonValue: [String: Any] {
        var value: [String: Any] = [
            "status": status,
            "summary": summary,
            "agent_type": agentType,
        ]
        if let requestedSteps {
            value["requested_steps"] = requestedSteps
        }
        return value
    }
}

public protocol ShortcutsServiceProtocol: Sendable {
    func runShortcut(named name: String, input: String?) async throws -> ShortcutsRunResult
}

public struct ShortcutsRunResult: Sendable {
    public let status: String
    public let shortcutName: String
    public let detail: String?

    public init(status: String, shortcutName: String, detail: String? = nil) {
        self.status = status
        self.shortcutName = shortcutName
        self.detail = detail
    }

    public var jsonValue: [String: Any] {
        var value: [String: Any] = [
            "status": status,
            "shortcut_name": shortcutName,
        ]
        if let detail {
            value["detail"] = detail
        }
        return value
    }
}
