import Foundation

public struct MessageCitation: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let index: Int
    public let title: String
    public let url: URL?
    public let snippet: String?

    public init(id: UUID = UUID(), index: Int, title: String, url: URL? = nil, snippet: String? = nil) {
        self.id = id
        self.index = index
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}
