import Foundation

public struct SSEEvent: Sendable, Equatable {
    public let event: String?
    public let data: String
    public let id: String?
    public let retry: Int?

    public init(event: String? = nil, data: String, id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }

    public var isDone: Bool {
        data == "[DONE]"
    }
}
