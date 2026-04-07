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

    public init(
        bookId: Int64? = nil,
        conversationId: String? = nil,
        database: (any ToolDatabaseAccess)? = nil,
        memoryDirectory: URL? = nil,
        httpClient: (any ToolHTTPClient)? = nil,
        calendarService: (any CalendarServiceProtocol)? = nil,
        remindersService: (any RemindersServiceProtocol)? = nil,
        subAgentService: (any SubAgentServiceProtocol)? = nil,
        shortcutsService: (any ShortcutsServiceProtocol)? = nil
    ) {
        self.bookId = bookId
        self.conversationId = conversationId
        self.database = database
        self.memoryDirectory = memoryDirectory
        self.httpClient = httpClient
        self.calendarService = calendarService
        self.remindersService = remindersService
        self.subAgentService = subAgentService
        self.shortcutsService = shortcutsService
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

    var jsonValue: [String: Any] {
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

    var jsonValue: [String: Any] {
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
