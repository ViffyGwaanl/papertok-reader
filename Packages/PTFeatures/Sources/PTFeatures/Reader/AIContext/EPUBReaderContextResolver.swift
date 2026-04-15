#if canImport(ReadiumShared)
import Foundation
import PTAIServices
import PTCore
import PTReader
import ReadiumShared

public final class EPUBReaderContextResolver: ReaderContextResolver, @unchecked Sendable {
    private let bridge: EPUBContentBridge
    private let book: Book
    private let clipper: BudgetedTextClipper
    private let cache: BookContentCache?

    public init(
        bridge: EPUBContentBridge,
        book: Book,
        clipper: BudgetedTextClipper = BudgetedTextClipper(),
        cache: BookContentCache? = nil
    ) {
        self.bridge = bridge
        self.book = book
        self.clipper = clipper
        self.cache = cache
    }

    private var cacheBookId: String {
        if let id = book.id { return String(id) }
        return book.filePath
    }

    public func resolve(
        scope: ReaderContextScope,
        currentLocator: AnyReaderLocator?,
        selection: String?
    ) async throws -> ReaderContextResult {
        let readiumLocator: Locator? = {
            guard case .epub(let locator) = currentLocator else { return nil }
            return locator
        }()

        let chapterTitle = readiumLocator?.title
        let author: String? = book.author.isEmpty ? nil : book.author

        switch scope {
        case .selection:
            guard let selection, selection.isEmpty == false else {
                throw ReaderContextError.noSelection
            }
            return ReaderContextResult(
                scope: .selection,
                bookTitle: book.title,
                bookAuthor: author,
                chapterTitle: chapterTitle,
                pageNumber: nil,
                totalPages: nil,
                text: selection,
                truncated: false,
                originalCharacterCount: selection.count
            )

        case .page:
            // Reflowable EPUB has no "page" concept. Approximate as a
            // window of paragraphs around the current locator: 2 before and
            // 5 after the nearest paragraph.
            guard let locator = readiumLocator else {
                throw ReaderContextError.missingLocator
            }
            let paragraphs = try await bridge.chapterParagraphs(at: locator)
            guard paragraphs.isEmpty == false else {
                return ReaderContextResult(
                    scope: .page,
                    bookTitle: book.title,
                    bookAuthor: author,
                    chapterTitle: chapterTitle,
                    pageNumber: nil,
                    totalPages: nil,
                    text: "",
                    truncated: false,
                    originalCharacterCount: 0
                )
            }
            let anchorProgression = locator.locations.progression ?? 0
            let anchorIndex = paragraphs
                .enumerated()
                .min(by: { lhs, rhs in
                    let l = abs((lhs.element.locator.locations.progression ?? 0) - anchorProgression)
                    let r = abs((rhs.element.locator.locations.progression ?? 0) - anchorProgression)
                    return l < r
                })?.offset ?? 0
            let start = max(0, anchorIndex - 2)
            let end = min(paragraphs.count - 1, anchorIndex + 5)
            let window = paragraphs[start...end].map(\.text).joined(separator: "\n\n")
            return ReaderContextResult(
                scope: .page,
                bookTitle: book.title,
                bookAuthor: author,
                chapterTitle: chapterTitle,
                pageNumber: nil,
                totalPages: nil,
                text: window,
                truncated: false,
                originalCharacterCount: window.count
            )

        case .chapter:
            guard let locator = readiumLocator else {
                throw ReaderContextError.missingLocator
            }
            let href = locator.href.string
            let cacheKey = BookContentCache.Key(
                bookId: cacheBookId,
                scope: .epubChapter(href: href)
            )
            let joined: String
            if let cache, let cached = await cache.get(cacheKey) {
                joined = cached
            } else {
                let paragraphs = try await bridge.chapterParagraphs(at: locator)
                joined = paragraphs.map(\.text).joined(separator: "\n\n")
                if let cache {
                    await cache.set(cacheKey, value: joined)
                }
            }
            return ReaderContextResult(
                scope: .chapter,
                bookTitle: book.title,
                bookAuthor: author,
                chapterTitle: chapterTitle,
                pageNumber: nil,
                totalPages: nil,
                text: joined,
                truncated: false,
                originalCharacterCount: joined.count
            )

        case .wholeBook:
            let wholeCacheKey = BookContentCache.Key(
                bookId: cacheBookId,
                scope: .epubWholeBook
            )
            let fullText: String
            if let cache, let cached = await cache.get(wholeCacheKey) {
                fullText = cached
            } else {
                var parts: [String] = []
                let entries = (try? await bridge.tableOfContents) ?? []
                for entry in entries {
                    let entryTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    do {
                        let paragraphs = try await bridge.chapterParagraphs(href: entry.href)
                        let joined = paragraphs.map(\.text).joined(separator: "\n\n")
                        guard joined.isEmpty == false else { continue }
                        if entryTitle.isEmpty == false {
                            parts.append("# \(entryTitle)\n\n\(joined)")
                        } else {
                            parts.append(joined)
                        }
                    } catch {
                        continue
                    }
                }
                fullText = parts.joined(separator: "\n\n")
                if let cache {
                    await cache.set(wholeCacheKey, value: fullText)
                }
            }
            let (clipped, truncated, originalCount) = clipper.clip(fullText)
            return ReaderContextResult(
                scope: .wholeBook,
                bookTitle: book.title,
                bookAuthor: author,
                chapterTitle: chapterTitle,
                pageNumber: nil,
                totalPages: nil,
                text: clipped,
                truncated: truncated,
                originalCharacterCount: originalCount
            )
        }
    }
}
#endif
