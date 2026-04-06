import Foundation

/// Context provided to AI tools during execution.
/// Contains references to the current book, conversation, and platform services.
public struct ToolContext: Sendable {
    public let bookId: Int64?
    public let conversationId: String?

    /// Calendar service for EventKit calendar operations (injected by App target).
    public let calendarService: (any CalendarServiceProtocol)?

    /// Reminders service for EventKit reminders operations (injected by App target).
    public let remindersService: (any RemindersServiceProtocol)?

    public init(
        bookId: Int64? = nil,
        conversationId: String? = nil,
        calendarService: (any CalendarServiceProtocol)? = nil,
        remindersService: (any RemindersServiceProtocol)? = nil
    ) {
        self.bookId = bookId
        self.conversationId = conversationId
        self.calendarService = calendarService
        self.remindersService = remindersService
    }
}
