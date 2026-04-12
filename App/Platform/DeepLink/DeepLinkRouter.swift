import SwiftUI
import Observation

/// Deep link destinations supported by PaperTok Reader.
///
/// URL Scheme: `paperreader://`
/// - `paperreader://reader/open?bookId={id}&href={href}` — primary reader route from `main`
/// - `paperreader://reader/open?bookId={id}&cfi={cfi}` — primary reader route from `main`
/// - `paperreader://book/{id}` — legacy open-book route
/// - `paperreader://reader/{id}` — legacy alias for opening a book by ID
/// - `paperreader://book?title={title}` — open book by title
/// - `paperreader://ai?message={text}` — open AI chat with pre-filled message
/// - `paperreader://ai?share_token={event-id}` — open AI chat with a shared event payload
/// - `paperreader://shortcuts/ask?question={text}` — quick ask route
/// - `paperreader://papers` — open Papers tab
/// - `paperreader://import?token={share-event-id}` — import files from the share inbox
public enum DeepLinkDestination: Equatable {
    case openBook(id: String? = nil, title: String? = nil, locator: String? = nil)
    case aiChat(initialMessage: String? = nil, shareToken: String? = nil)
    case quickAsk(initialMessage: String? = nil, shareToken: String? = nil)
    case papers
    case importFile(token: String? = nil)
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
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        func queryValue(named names: [String]) -> String? {
            for name in names {
                if let value = query.first(where: { $0.name == name })?.value,
                   value.isEmpty == false {
                    return value
                }
            }
            return nil
        }

        switch host {
        case "book":
            let id = pathComponents.first
            let title = queryValue(named: ["title"])
            return .openBook(id: id, title: title)
        case "reader":
            if pathComponents.first?.lowercased() == "open" {
                let id = queryValue(named: ["bookId", "bookID", "book_id", "bookld", "bookLd", "id"])
                    ?? pathComponents.dropFirst().first
                let title = queryValue(named: ["title"])
                let locator = queryValue(named: ["locator", "cfi", "page", "href"])
                return .openBook(id: id, title: title, locator: locator)
            }

            let id = pathComponents.first
            let title = queryValue(named: ["title"])
            return .openBook(id: id, title: title)
        case "ai":
            let message = queryValue(named: ["message", "question", "prompt"])
            let shareToken = queryValue(named: ["share_token", "token"])
            return .aiChat(initialMessage: message, shareToken: shareToken)
        case "shortcuts":
            if pathComponents.first == "ask" {
                let message = queryValue(named: ["question", "message", "prompt"])
                let shareToken = queryValue(named: ["share_token", "token"])
                return .quickAsk(initialMessage: message, shareToken: shareToken)
            }
            return nil
        case "papers":
            return .papers
        case "import":
            return .importFile(token: queryValue(named: ["token", "id"]))
        default:
            return nil
        }
    }
}
