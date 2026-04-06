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

    public init(
        bookId: Int64? = nil,
        conversationId: String? = nil,
        database: (any ToolDatabaseAccess)? = nil,
        memoryDirectory: URL? = nil,
        httpClient: (any ToolHTTPClient)? = nil,
        calendarService: (any CalendarServiceProtocol)? = nil,
        remindersService: (any RemindersServiceProtocol)? = nil
    ) {
        self.bookId = bookId
        self.conversationId = conversationId
        self.database = database
        self.memoryDirectory = memoryDirectory
        self.httpClient = httpClient
        self.calendarService = calendarService
        self.remindersService = remindersService
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
