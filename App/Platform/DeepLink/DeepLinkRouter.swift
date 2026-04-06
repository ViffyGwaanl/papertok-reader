import SwiftUI
import Observation

/// Deep link destinations supported by PaperTok Reader.
///
/// URL Scheme: `paperreader://`
/// - `paperreader://book/{id}` — open book by ID
/// - `paperreader://book?title={title}` — open book by title
/// - `paperreader://ai?message={text}` — open AI chat with pre-filled message
/// - `paperreader://papers` — open Papers tab
/// - `paperreader://import` — open file importer
public enum DeepLinkDestination: Equatable {
    case openBook(id: String? = nil, title: String? = nil)
    case aiChat(initialMessage: String? = nil)
    case papers
    case importFile
}

/// Singleton router that holds a pending deep link destination.
/// Views observe `pendingDestination` to navigate accordingly.
@Observable
public final class DeepLinkRouter {
    public static let shared = DeepLinkRouter()
    public var pendingDestination: DeepLinkDestination?

    private init() {}

    public func route(to destination: DeepLinkDestination) {
        pendingDestination = destination
    }

    /// Parse and route a URL. Returns `true` if the URL was handled.
    @discardableResult
    public func handle(url: URL) -> Bool {
        guard let destination = DeepLinkParser.parse(url: url) else { return false }
        route(to: destination)
        return true
    }

    /// Consume the pending destination (called after navigation is performed).
    public func consumeDestination() {
        pendingDestination = nil
    }
}

// MARK: - DeepLinkParser

public enum DeepLinkParser {
    public static func parse(url: URL) -> DeepLinkDestination? {
        guard url.scheme == "paperreader" else { return nil }
        let host = url.host ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []

        switch host {
        case "book":
            let id = url.pathComponents.dropFirst().first
            let title = query.first(where: { $0.name == "title" })?.value
            return .openBook(id: id, title: title)
        case "ai":
            let message = query.first(where: { $0.name == "message" })?.value
            return .aiChat(initialMessage: message)
        case "papers":
            return .papers
        case "import":
            return .importFile
        default:
            return nil
        }
    }
}
