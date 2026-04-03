import Foundation

public struct ToolContext: Sendable {
    public let bookId: Int64?
    public let conversationId: String?
    public init(bookId: Int64? = nil, conversationId: String? = nil) {
        self.bookId = bookId; self.conversationId = conversationId
    }
}
