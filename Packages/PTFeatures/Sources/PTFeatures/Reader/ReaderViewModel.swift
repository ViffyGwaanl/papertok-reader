import Foundation
import Observation
import PDFKit
import SwiftUI
import PTCore
import PTAIServices
import PTReader

@MainActor @Observable
public final class ReaderViewModel {
    // MARK: - Published state
    public private(set) var pageCount: Int = 0
    /// Current page index. Setting this clamps to [0, pageCount-1] and updates readingPercentage.
    public var currentPage: Int = 0 {
        didSet {
            guard pageCount > 0 else { return }
            let clamped = max(0, min(currentPage, pageCount - 1))
            if clamped != currentPage { currentPage = clamped; return }
            readingPercentage = pageCount > 1
                ? Double(currentPage) / Double(pageCount - 1)
                : 1.0
            recomputeBookmarkFlag()
            publishReaderSession()
        }
    }
    public private(set) var readingPercentage: Double = 0
    public private(set) var tocEntries: [ChapterEntry] = []
    public var showTOC: Bool = false
    public private(set) var isLoading: Bool = false

    // MARK: - Internal state
    public private(set) var pdfDocument: PDFDocument?
    public let book: Book
    private let bookDAO: BookDAO
    private let noteDAO: BookNoteDAO
    private let readingSessionRecorder: ReadingSessionRecorder
    private let readerSessionStore: ReaderSessionContextStore?
    public private(set) var pdfContentBridge: PDFContentBridge?

    /// Whether the current page already has a bookmark.
    public private(set) var isCurrentPageBookmarked: Bool = false
    private var bookmarkCache: [BookNote] = []

    public var contentBridge: (any BookContentBridge)? {
        pdfContentBridge
    }

    public init(
        book: Book,
        database: AppDatabase,
        readerSessionStore: ReaderSessionContextStore? = nil,
        initialPageOverride: Int? = nil
    ) {
        self.book = book
        self.bookDAO = BookDAO(database: database)
        self.noteDAO = BookNoteDAO(database: database)
        self.readingSessionRecorder = ReadingSessionRecorder(bookId: book.id, database: database)
        self.readerSessionStore = readerSessionStore
        self.currentPage = initialPageOverride ?? Int(book.lastReadPosition) ?? 0
        self.readingPercentage = book.readingPercentage
    }

    // MARK: - Document loading

    public func loadDocument() async {
        isLoading = true
        defer { isLoading = false }

        let url = URL(fileURLWithPath: book.filePath)
        guard let doc = PDFDocument(url: url) else {
            readerSessionStore?.clear()
            return
        }

        pdfDocument = doc
        pageCount = doc.pageCount

        // Clamp restored page to valid range
        if pageCount > 0 {
            currentPage = max(0, min(currentPage, pageCount - 1))
        }

        // Build TOC from PDF outline. Prefer the real hierarchical outline
        // parser; fall back to the service-layer synthetic chapter grouping
        // when the document has no outline.
        let bridge = PDFContentBridge(document: doc, title: book.title)
        pdfContentBridge = bridge
        let outline = await bridge.outlineChapters()
        if outline.isEmpty {
            tocEntries = (try? await bridge.tableOfContents) ?? []
        } else {
            tocEntries = Self.flattenOutline(outline, totalPageCount: pageCount)
        }
        publishReaderSession()
        await loadBookmarks()
        await readingSessionRecorder.resume()
    }

    // MARK: - Navigation

    public func goToPage(_ page: Int) {
        currentPage = page  // didSet handles clamping and percentage update
    }

    public func goToChapter(href: String) {
        guard let range = PDFChapter.parsePageRange(from: href) else { return }
        goToPage(range.startPage)
    }

    // MARK: - Progress persistence

    public func saveProgress() async {
        guard let bookId = book.id,
              var updatedBook = try? await bookDAO.fetchById(bookId) else { return }
        updatedBook.readingPercentage = readingPercentage
        updatedBook.lastReadPosition = "\(currentPage)"
        updatedBook.updateTime = Date()
        _ = try? await bookDAO.save(updatedBook)
    }

    public func handleScenePhaseChange(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            await readingSessionRecorder.resume()
        case .inactive:
            await readingSessionRecorder.pause()
        case .background:
            _ = try? await readingSessionRecorder.flush()
        @unknown default:
            await readingSessionRecorder.pause()
        }
    }

    public func endReadingSession() async {
        _ = try? await readingSessionRecorder.flush()
    }

    private func publishReaderSession() {
        guard let readerSessionStore, let pdfContentBridge else { return }
        let adapter = ReaderSessionToolBridgeAdapter(bridge: pdfContentBridge)
        let chapter = currentChapterEntry ?? ChapterEntry(
            title: Self.localizedPageLabel(for: currentPage),
            href: "pages:\(currentPage)-\(currentPage)"
        )
        readerSessionStore.update(
            ReaderSessionSnapshot(
                bookId: book.id,
                readingProgress: readingPercentage,
                chapterTitle: chapter.title,
                locationHref: chapter.href,
                contentBridgeProvider: { adapter }
            )
        )
    }

    // MARK: - Bookmarks

    /// Reload bookmarks for the current book from the database.
    @discardableResult
    public func loadBookmarks() async -> [BookNote] {
        guard let bookId = book.id else {
            bookmarkCache = []
            recomputeBookmarkFlag()
            return []
        }
        do {
            let notes = try await noteDAO.fetchByBookId(bookId)
            bookmarkCache = notes.filter { $0.type == NoteType.bookmark.rawValue }
            recomputeBookmarkFlag()
            return bookmarkCache
        } catch {
            return bookmarkCache
        }
    }

    /// Toggle bookmark for the currently displayed page. If a bookmark
    /// already exists on this page it is deleted, otherwise a new one
    /// is created.
    public func toggleBookmark() async {
        guard let bookId = book.id else { return }
        let pageIndex = currentPage
        let pageLabel = pdfDocument?.page(at: pageIndex)?.label ?? Self.localizedPageLabel(for: pageIndex)

        if let existing = bookmark(forPage: pageIndex), let id = existing.id {
            try? await noteDAO.delete(id: id)
        } else {
            let anchor = PDFAnnotationAnchor.bookmark(pageIndex: pageIndex, pageLabel: pageLabel)
            let locatorString = PDFAnnotationBridge.storedString(from: anchor)
            let now = Date()
            let note = BookNote(
                bookId: bookId,
                content: pageLabel,
                cfi: locatorString,
                chapter: currentChapterEntry?.title ?? pageLabel,
                type: NoteType.bookmark.rawValue,
                color: HighlightColor.yellow.hex,
                readerNote: nil,
                createTime: now,
                updateTime: now
            )
            _ = try? await noteDAO.save(note)
        }

        await loadBookmarks()
    }

    /// Delete a single bookmark by id.
    public func deleteBookmark(id: Int64) async {
        try? await noteDAO.delete(id: id)
        await loadBookmarks()
    }

    /// Jump to the page referenced by the given bookmark.
    public func jumpToBookmark(_ note: BookNote) {
        if let anchor = PDFAnnotationBridge.anchor(fromStoredString:note.cfi) {
            goToPage(anchor.pageIndex)
        }
    }

    private func bookmark(forPage pageIndex: Int) -> BookNote? {
        bookmarkCache.first { note in
            guard let anchor = PDFAnnotationBridge.anchor(fromStoredString:note.cfi) else {
                return false
            }
            return anchor.kind == .bookmark && anchor.pageIndex == pageIndex
        }
    }

    private func recomputeBookmarkFlag() {
        isCurrentPageBookmarked = bookmark(forPage: currentPage) != nil
    }

    private var currentChapterEntry: ChapterEntry? {
        tocEntries.first(where: { entry in
            guard let range = PDFChapter.parsePageRange(from: entry.href) else { return false }
            return range.startPage <= currentPage && currentPage <= range.endPage
        })
    }

    /// Public accessor for the current chapter's title, used by reader UI
    /// (e.g. the TTS floating action button). Falls back to the book title
    /// when no TOC entry matches the current page.
    public var currentChapterTitle: String {
        currentChapterEntry?.title ?? book.title
    }

    static func localizedPageLabel(for pageIndex: Int) -> String {
        localizedCatalogFormat("reader.page_number_format", pageIndex + 1)
    }

    /// Flattens a hierarchical PDF outline into ChapterEntry rows. Child
    /// titles are prefixed with two spaces per depth level so the existing
    /// flat TOC list surfaces the hierarchy without a tree UI. End pages are
    /// derived from the next entry's start page (document order preserved).
    static func flattenOutline(
        _ outline: [PDFOutlineChapter],
        totalPageCount: Int
    ) -> [ChapterEntry] {
        let flat = outline.flattened()
        guard flat.isEmpty == false else { return [] }
        var entries: [ChapterEntry] = []
        for (i, chapter) in flat.enumerated() {
            let nextStart = (i + 1 < flat.count) ? flat[i + 1].pageIndex : totalPageCount
            let endPage = max(chapter.pageIndex, nextStart - 1)
            let indent = String(repeating: "  ", count: chapter.depth)
            let title = indent + chapter.title
            let href = "pages:\(chapter.pageIndex)-\(endPage)"
            entries.append(ChapterEntry(title: title, href: href, level: chapter.depth))
        }
        return entries
    }
}

private func localizedCatalogString(_ key: String, locale: Locale = .autoupdatingCurrent) -> String {
    String(localized: String.LocalizationValue(key), bundle: localizedCatalogBundle(), locale: locale)
}

private func localizedCatalogFormat(_ key: String, locale: Locale = .autoupdatingCurrent, _ arguments: CVarArg...) -> String {
    String(format: localizedCatalogString(key, locale: locale), locale: locale, arguments: arguments)
}

private func localizedCatalogBundle() -> Bundle {
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
