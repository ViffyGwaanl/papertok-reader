import Foundation
import PTCore

#if canImport(ReadiumShared)
import ReadiumShared
#endif

// MARK: - Scope / Result / Errors

public enum ReaderContextScope: String, Hashable, Sendable, CaseIterable, Codable {
    case selection
    case page
    case chapter
    case wholeBook
}

public struct ReaderContextResult: Hashable, Sendable {
    public let scope: ReaderContextScope
    public let bookTitle: String
    public let bookAuthor: String?
    public let chapterTitle: String?
    public let pageNumber: Int?
    public let totalPages: Int?
    public let text: String
    public let truncated: Bool
    public let originalCharacterCount: Int

    public init(
        scope: ReaderContextScope,
        bookTitle: String,
        bookAuthor: String?,
        chapterTitle: String?,
        pageNumber: Int?,
        totalPages: Int?,
        text: String,
        truncated: Bool,
        originalCharacterCount: Int
    ) {
        self.scope = scope
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.chapterTitle = chapterTitle
        self.pageNumber = pageNumber
        self.totalPages = totalPages
        self.text = text
        self.truncated = truncated
        self.originalCharacterCount = originalCharacterCount
    }
}

public enum ReaderContextError: Error, Equatable, Sendable {
    case noSelection
    case missingLocator
    case contentUnavailable(String)
}

public enum AnyReaderLocator: Sendable {
    #if canImport(ReadiumShared)
    case epub(ReadiumShared.Locator)
    #endif
    case pdf(pageIndex: Int)
}

public protocol ReaderContextResolver: Sendable {
    func resolve(
        scope: ReaderContextScope,
        currentLocator: AnyReaderLocator?,
        selection: String?
    ) async throws -> ReaderContextResult
}

// MARK: - BudgetedTextClipper

public struct BudgetedTextClipper: Sendable {
    public let maxCharacters: Int

    public init(maxCharacters: Int = 80_000) {
        self.maxCharacters = maxCharacters
    }

    public func clip(_ text: String) -> (clipped: String, wasTruncated: Bool, originalCount: Int) {
        let originalCount = text.count
        guard originalCount > maxCharacters else {
            return (text, false, originalCount)
        }

        let budget = max(0, maxCharacters)
        let cutoffIndex = text.index(text.startIndex, offsetBy: budget, limitedBy: text.endIndex) ?? text.endIndex
        var clipped = String(text[..<cutoffIndex])

        // Prefer cutting at a paragraph boundary if one exists reasonably close
        // to the budget, otherwise fall back to the character cutoff.
        if let range = clipped.range(of: "\n\n", options: .backwards) {
            let distance = clipped.distance(from: range.lowerBound, to: clipped.endIndex)
            // Only snap to the paragraph boundary if it's within the last 20%
            // of the budget so we don't lose huge amounts of content.
            if distance <= max(1, budget / 5) {
                clipped = String(clipped[..<range.lowerBound])
            }
        }

        let trimmed = clipped.trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = localizedCatalogString("reader.context.truncated_marker")
        let finalText = trimmed + "\n\n" + marker
        return (finalText, true, originalCount)
    }
}

// MARK: - Preamble Builder

public struct ReaderContextPreambleBuilder: Sendable {
    public init() {}

    public func buildPreamble(for result: ReaderContextResult, locale: Locale = .autoupdatingCurrent) -> String {
        var lines: [String] = []

        let title = result.bookTitle
        if let author = result.bookAuthor, author.isEmpty == false {
            lines.append(
                localizedCatalogFormat(
                    "reader.context.preamble.book_intro_format",
                    locale: locale,
                    title,
                    author
                )
            )
        } else {
            lines.append(
                localizedCatalogFormat(
                    "reader.context.preamble.book_intro_no_author_format",
                    locale: locale,
                    title
                )
            )
        }

        if let chapter = result.chapterTitle, chapter.isEmpty == false {
            lines.append(
                localizedCatalogFormat(
                    "reader.context.preamble.chapter_format",
                    locale: locale,
                    chapter
                )
            )
        }

        let scopeName = localizedCatalogString(scopeKey(result.scope), locale: locale)
        lines.append(
            localizedCatalogFormat(
                "reader.context.preamble.scope_format",
                locale: locale,
                scopeName
            )
        )

        if let page = result.pageNumber, let total = result.totalPages, total > 0 {
            lines.append(
                localizedCatalogFormat(
                    "reader.context.preamble.page_format",
                    locale: locale,
                    page,
                    total
                )
            )
        }

        let header = lines.joined(separator: "\n")
        let body = result.text
        return header + "\n\n---\n\n" + body
    }

    public func scopeKey(_ scope: ReaderContextScope) -> String {
        switch scope {
        case .selection: return "reader.context.scope.selection"
        case .page: return "reader.context.scope.page"
        case .chapter: return "reader.context.scope.chapter"
        case .wholeBook: return "reader.context.scope.whole_book"
        }
    }
}

// MARK: - Helpers

private func localizedCatalogString(_ key: String, locale: Locale = .autoupdatingCurrent) -> String {
    String(localized: String.LocalizationValue(key), bundle: readerContextBundle(), locale: locale)
}

private func localizedCatalogFormat(_ key: String, locale: Locale = .autoupdatingCurrent, _ arguments: CVarArg...) -> String {
    String(format: localizedCatalogString(key, locale: locale), locale: locale, arguments: arguments)
}

private func readerContextBundle() -> Bundle {
    let bundles = Bundle.allBundles + Bundle.allFrameworks

    if Bundle.main.bundleURL.pathExtension == "app" {
        return .main
    }
    if let appBundle = bundles.first(where: { $0.bundleIdentifier == "ai.papertok.paperreader" }) {
        return appBundle
    }
    let candidateDirectories = Set(bundles.map { $0.bundleURL.deletingLastPathComponent() })
    for directory in candidateDirectories {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { continue }

        for candidateURL in urls where candidateURL.pathExtension == "app" {
            if let appBundle = Bundle(url: candidateURL),
               appBundle.bundleIdentifier == "ai.papertok.paperreader" {
                return appBundle
            }
        }
    }
    return bundles.first(where: { $0.bundleURL.pathExtension == "app" }) ?? .main
}
