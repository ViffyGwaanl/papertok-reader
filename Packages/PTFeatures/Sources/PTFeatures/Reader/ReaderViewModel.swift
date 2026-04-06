import Foundation
import Observation
import PDFKit
import PTCore
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

    public init(book: Book, database: AppDatabase) {
        self.book = book
        self.bookDAO = BookDAO(database: database)
        self.currentPage = Int(book.lastReadPosition) ?? 0
        self.readingPercentage = book.readingPercentage
    }

    // MARK: - Document loading

    public func loadDocument() async {
        isLoading = true
        defer { isLoading = false }

        let url = URL(fileURLWithPath: book.filePath)
        guard let doc = PDFDocument(url: url) else { return }

        pdfDocument = doc
        pageCount = doc.pageCount

        // Clamp restored page to valid range
        if pageCount > 0 {
            currentPage = max(0, min(currentPage, pageCount - 1))
        }

        // Build TOC from PDF outline
        let bridge = PDFContentBridge(document: doc, title: book.title)
        let chapters = bridge.segmentByOutline()
        if chapters.isEmpty {
            // Use synthetic chapters (every 20 pages)
            tocEntries = (try? await bridge.tableOfContents) ?? []
        } else {
            tocEntries = chapters.map { $0.toChapterEntry() }
        }
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
}
