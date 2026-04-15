#if canImport(PDFKit)
import Foundation
import PTCore
import PTReader

@MainActor
public final class PDFReaderContextResolver: ReaderContextResolver {
    private let bridge: PDFContentBridge
    private let book: Book
    private let currentPageProvider: @MainActor () -> Int
    private let clipper: BudgetedTextClipper

    public init(
        bridge: PDFContentBridge,
        book: Book,
        currentPageProvider: @escaping @MainActor () -> Int,
        clipper: BudgetedTextClipper = BudgetedTextClipper()
    ) {
        self.bridge = bridge
        self.book = book
        self.currentPageProvider = currentPageProvider
        self.clipper = clipper
    }

    public nonisolated func resolve(
        scope: ReaderContextScope,
        currentLocator: AnyReaderLocator?,
        selection: String?
    ) async throws -> ReaderContextResult {
        try await performResolve(scope: scope, currentLocator: currentLocator, selection: selection)
    }

    @MainActor
    private func performResolve(
        scope: ReaderContextScope,
        currentLocator: AnyReaderLocator?,
        selection: String?
    ) async throws -> ReaderContextResult {
        let totalPages = bridge.pageCount
        let resolvedPage: Int = {
            if case .pdf(let pageIndex) = currentLocator { return pageIndex }
            return currentPageProvider()
        }()
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
                chapterTitle: chapterTitleForPage(resolvedPage, flatChapters: await bridge.outlineChapters().flattened()),
                pageNumber: resolvedPage + 1,
                totalPages: totalPages,
                text: selection,
                truncated: false,
                originalCharacterCount: selection.count
            )

        case .page:
            let text = bridge.extractPageText(page: resolvedPage)
            let flat = await bridge.outlineChapters().flattened()
            return ReaderContextResult(
                scope: .page,
                bookTitle: book.title,
                bookAuthor: author,
                chapterTitle: chapterTitleForPage(resolvedPage, flatChapters: flat),
                pageNumber: resolvedPage + 1,
                totalPages: totalPages,
                text: text,
                truncated: false,
                originalCharacterCount: text.count
            )

        case .chapter:
            let flat = await bridge.outlineChapters().flattened()
            let (start, end, title) = chapterRange(for: resolvedPage, flatChapters: flat, totalPages: totalPages)
            // Cap chapter assembly at 200 pages to bound worst case.
            let capped = min(end, start + 200 - 1)
            var parts: [String] = []
            if capped >= start {
                for page in start...capped {
                    let text = bridge.extractPageText(page: page)
                    if text.isEmpty == false { parts.append(text) }
                }
            }
            let joined = parts.joined(separator: "\n\n")
            return ReaderContextResult(
                scope: .chapter,
                bookTitle: book.title,
                bookAuthor: author,
                chapterTitle: title,
                pageNumber: resolvedPage + 1,
                totalPages: totalPages,
                text: joined,
                truncated: false,
                originalCharacterCount: joined.count
            )

        case .wholeBook:
            var parts: [String] = []
            for page in 0..<totalPages {
                let text = bridge.extractPageText(page: page)
                if text.isEmpty == false { parts.append(text) }
            }
            let full = parts.joined(separator: "\n\n")
            let (clipped, truncated, originalCount) = clipper.clip(full)
            let flat = await bridge.outlineChapters().flattened()
            return ReaderContextResult(
                scope: .wholeBook,
                bookTitle: book.title,
                bookAuthor: author,
                chapterTitle: chapterTitleForPage(resolvedPage, flatChapters: flat),
                pageNumber: resolvedPage + 1,
                totalPages: totalPages,
                text: clipped,
                truncated: truncated,
                originalCharacterCount: originalCount
            )
        }
    }

    // MARK: - Chapter lookup

    private func chapterTitleForPage(_ page: Int, flatChapters: [PDFOutlineChapter]) -> String? {
        chapterEntry(for: page, flatChapters: flatChapters)?.title
    }

    private func chapterEntry(for page: Int, flatChapters: [PDFOutlineChapter]) -> PDFOutlineChapter? {
        guard flatChapters.isEmpty == false else { return nil }
        var current: PDFOutlineChapter?
        for chapter in flatChapters {
            if chapter.pageIndex <= page { current = chapter } else { break }
        }
        return current
    }

    private func chapterRange(
        for page: Int,
        flatChapters: [PDFOutlineChapter],
        totalPages: Int
    ) -> (start: Int, end: Int, title: String?) {
        guard flatChapters.isEmpty == false else {
            return (0, max(0, totalPages - 1), nil)
        }
        var currentIndex: Int?
        for (index, chapter) in flatChapters.enumerated() {
            if chapter.pageIndex <= page { currentIndex = index } else { break }
        }
        guard let idx = currentIndex else {
            let first = flatChapters[0]
            let end = flatChapters.count > 1 ? flatChapters[1].pageIndex - 1 : totalPages - 1
            return (first.pageIndex, max(first.pageIndex, end), first.title)
        }
        let chapter = flatChapters[idx]
        let nextStart = (idx + 1 < flatChapters.count) ? flatChapters[idx + 1].pageIndex : totalPages
        return (chapter.pageIndex, max(chapter.pageIndex, nextStart - 1), chapter.title)
    }
}
#endif
