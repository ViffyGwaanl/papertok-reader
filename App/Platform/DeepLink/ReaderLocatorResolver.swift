import Foundation
import PTCore

/// Resolves `paperreader://reader/open?bookId=...&locator=...` deep links into a
/// concrete `Book` + reader starting position.
///
/// Supported locator formats:
/// - `cfi:epubcfi(/6/4[chap01]!/4/2/1:0)` for EPUB
/// - `page:42` for PDFs
/// - Raw CFI strings beginning with `epubcfi(`
/// - Raw numeric strings (interpreted as PDF page numbers)
public struct ReaderLocatorResolver: Sendable {
    public enum ResolvedLocator: Sendable, Equatable {
        case cfi(String)
        case page(Int)
    }

    public struct Resolved: Sendable, Equatable {
        public let book: Book
        public let locator: ResolvedLocator?

        public init(book: Book, locator: ResolvedLocator?) {
            self.book = book
            self.locator = locator
        }
    }

    public enum ResolveError: Error, LocalizedError, Sendable {
        case missingBookId
        case invalidBookId(String)
        case bookNotFound(Int64)
        case invalidLocator(String)

        public var errorDescription: String? {
            switch self {
            case .missingBookId:
                return AppLocalization.string(
                    "errors.deeplink.missing_book_id",
                    value: "Missing bookId in deep link."
                )
            case .invalidBookId(let raw):
                return AppLocalization.format(
                    "errors.deeplink.invalid_book_id_format",
                    "Invalid bookId: %@",
                    raw
                )
            case .bookNotFound(let id):
                return AppLocalization.format(
                    "errors.deeplink.book_not_found_format",
                    "Book #%lld not found.",
                    id
                )
            case .invalidLocator(let raw):
                return AppLocalization.format(
                    "errors.deeplink.invalid_locator_format",
                    "Invalid locator: %@",
                    raw
                )
            }
        }
    }

    private let bookDAO: BookDAO

    public init(bookDAO: BookDAO) {
        self.bookDAO = bookDAO
    }

    // MARK: - URL parsing

    /// Attempts to parse a `paperreader://reader/open?bookId=...&locator=...` URL.
    ///
    /// Returns `nil` if the URL is not a reader-open URL.
    public static func parse(url: URL) -> (bookId: String, locator: String?)? {
        guard url.scheme == "paperreader", url.host == "reader" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.first?.lowercased() == "open" else { return nil }

        let query = components?.queryItems ?? []
        func value(_ names: [String]) -> String? {
            for name in names {
                if let v = query.first(where: { $0.name == name })?.value, v.isEmpty == false {
                    return v
                }
            }
            return nil
        }

        guard let bookId = value(["bookId", "bookID", "book_id", "id"]) else { return nil }
        let locator = value(["locator", "cfi", "page", "href"])
        return (bookId: bookId, locator: locator)
    }

    // MARK: - Resolution

    /// Resolve a parsed deep link into a Book + locator pair.
    public func resolve(bookIdString: String, locatorString: String?) async throws -> Resolved {
        guard let id = Int64(bookIdString) else {
            throw ResolveError.invalidBookId(bookIdString)
        }
        guard let book = try await bookDAO.fetchById(id) else {
            throw ResolveError.bookNotFound(id)
        }

        guard let raw = locatorString, raw.isEmpty == false else {
            return Resolved(book: book, locator: nil)
        }

        let locator = try Self.parseLocator(raw)
        return Resolved(book: book, locator: locator)
    }

    /// Convenience that parses a URL and resolves it in one step.
    public func resolve(url: URL) async throws -> Resolved {
        guard let parsed = Self.parse(url: url) else {
            throw ResolveError.missingBookId
        }
        return try await resolve(bookIdString: parsed.bookId, locatorString: parsed.locator)
    }

    // MARK: - Locator parsing

    internal static func parseLocator(_ raw: String) throws -> ResolvedLocator {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ResolveError.invalidLocator(raw)
        }

        let lower = trimmed.lowercased()

        // Explicit prefixes
        if lower.hasPrefix("cfi:") {
            let value = String(trimmed.dropFirst(4))
            guard value.isEmpty == false else { throw ResolveError.invalidLocator(raw) }
            return .cfi(value)
        }
        if lower.hasPrefix("page:") {
            let value = String(trimmed.dropFirst(5))
            guard let page = Int(value), page > 0 else { throw ResolveError.invalidLocator(raw) }
            return .page(page)
        }

        // Heuristic: epubcfi(...) is a CFI
        if lower.hasPrefix("epubcfi(") {
            return .cfi(trimmed)
        }

        // Pure numeric → PDF page
        if let page = Int(trimmed), page > 0 {
            return .page(page)
        }

        // Anything else with slashes we treat as an href/CFI-like string.
        if trimmed.contains("/") || trimmed.contains("!") {
            return .cfi(trimmed)
        }

        throw ResolveError.invalidLocator(raw)
    }
}
