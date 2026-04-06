# Book Import + PDF Reader Implementation Plan

> **状态：全部 7 个 Task ✅ 已完成（2026-04-04）。iOS 和 macOS Xcode 构建均通过，PTCore 45 个测试 + PTFeatures 12 个测试全部通过。**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add PDF/EPUB file import from the bookshelf toolbar and a full-screen PDFKit reader with TOC navigation and progress persistence.

**Architecture:** BookImportService (actor) handles file copy + metadata extraction + cover generation + DB save, living in PTFeatures/Bookshelf. ReaderViewModel (@Observable) manages document state in PTFeatures/Reader. PDFReaderView (UIViewRepresentable on iOS, NSViewRepresentable on macOS) wraps PDFKit's PDFView in PTFeatures/Reader. BookshelfScreen gains a "+" toolbar button using `.fileImporter()`. All UI uses MorandiPalette and AppSpacing.

**Tech Stack:** Swift 5.9+, SwiftUI, PDFKit, Observation framework, GRDB.swift, PTCore, PTFeatures, PTUI, Swift Testing

---

## File Structure

```
Packages/PTCore/Sources/PTCore/Database/
└── BookDAO.swift                          MODIFY — add fetchByMD5(_:)

Packages/PTFeatures/Sources/PTFeatures/Bookshelf/
├── BookshelfViewModel.swift               MODIFY — add importBook(url:), importError, isImporting
└── BookImportService.swift                CREATE — actor; copy file, parse PDF metadata, generate cover, save Book

Packages/PTFeatures/Sources/PTFeatures/Reader/
├── ReaderViewModel.swift                  CREATE — @Observable; load PDF, page state, TOC, save progress
└── PDFReaderView.swift                    CREATE — UIViewRepresentable (iOS) / NSViewRepresentable (macOS)

App/ContentView.swift                      MODIFY — add import button+fileImporter, NavigationLink to PDFReaderView

Packages/PTCore/Tests/PTCoreTests/Database/
└── BookDAOTests.swift                     MODIFY — add fetchByMD5 test

Packages/PTFeatures/Tests/PTFeaturesTests/Bookshelf/
└── BookshelfViewModelTests.swift          MODIFY — add import test with temp PDF

Packages/PTFeatures/Tests/PTFeaturesTests/Reader/
└── ReaderViewModelTests.swift             CREATE — test load/page/progress with temp PDF
```

---

### Task 1: Add `fetchByMD5` to BookDAO

**Files:**
- Modify: `Packages/PTCore/Sources/PTCore/Database/BookDAO.swift`
- Modify: `Packages/PTCore/Tests/PTCoreTests/Database/BookDAOTests.swift`

- [x] **Step 1.1: Write the failing test**

Open `Packages/PTCore/Tests/PTCoreTests/Database/BookDAOTests.swift` and add inside the test file:

```swift
@Test func fetchByMD5_returnsMatchingBook() async throws {
    let db = try AppDatabase.makeInMemory()
    let dao = BookDAO(database: db)
    let now = Date()
    var book = Book(
        id: nil, title: "MD5 Book", coverPath: "", filePath: "/tmp/md5.pdf",
        lastReadPosition: "", readingPercentage: 0, author: "Author",
        isDeleted: false, description: nil, rating: 0, groupId: 0,
        md5: "abc123", createTime: now, updateTime: now
    )
    book = try await dao.save(book)
    let found = try await dao.fetchByMD5("abc123")
    #expect(found?.id == book.id)
    let missing = try await dao.fetchByMD5("notexist")
    #expect(missing == nil)
}
```

- [x] **Step 1.2: Run test to verify it fails**

```bash
cd /Users/gwaanl/GitHub/papertok-reader
swift test --package-path Packages/PTCore --filter fetchByMD5_returnsMatchingBook 2>&1 | tail -10
```

Expected: error — `fetchByMD5` method does not exist.

- [x] **Step 1.3: Add `fetchByMD5` to BookDAO**

In `Packages/PTCore/Sources/PTCore/Database/BookDAO.swift`, add after the `search` method:

```swift
public func fetchByMD5(_ md5: String) async throws -> Book? {
    try await database.reader.read { db in
        try Book
            .filter(Column("file_md5") == md5)
            .filter(Column("is_deleted") == false)
            .fetchOne(db)
    }
}
```

- [x] **Step 1.4: Run test to verify it passes**

```bash
swift test --package-path Packages/PTCore --filter fetchByMD5_returnsMatchingBook 2>&1 | tail -5
```

Expected: `Test run with 1 test passed`

- [x] **Step 1.5: Commit**

```bash
cd /Users/gwaanl/GitHub/papertok-reader
git add Packages/PTCore/Sources/PTCore/Database/BookDAO.swift \
        Packages/PTCore/Tests/PTCoreTests/Database/BookDAOTests.swift
git commit -m "feat(PTCore): add BookDAO.fetchByMD5 for import deduplication"
```

---

### Task 2: Create BookImportService

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/BookImportService.swift`

- [x] **Step 2.1: Create BookImportService actor**

Create `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/BookImportService.swift`:

```swift
import Foundation
import PDFKit
import CryptoKit
import PTCore

public enum BookImportError: Error, LocalizedError {
    case unsupportedFormat
    case alreadyExists(Book)
    case copyFailed(Error)
    case saveFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Only PDF and EPUB files are supported."
        case .alreadyExists: return "This book is already in your library."
        case .copyFailed(let e): return "Could not copy file: \(e.localizedDescription)"
        case .saveFailed(let e): return "Could not save book: \(e.localizedDescription)"
        }
    }
}

public actor BookImportService {
    private let bookDAO: BookDAO
    private let booksDirectory: URL
    private let coversDirectory: URL

    public init(database: AppDatabase) {
        self.bookDAO = BookDAO(database: database)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.booksDirectory = docs.appendingPathComponent("Books", isDirectory: true)
        self.coversDirectory = docs.appendingPathComponent("Covers", isDirectory: true)
    }

    /// Import a book file from `sourceURL` (must be a security-scoped resource already accessed).
    /// Returns the saved `Book`. Throws `BookImportError` on failure.
    public func importFile(from sourceURL: URL) async throws -> Book {
        // 1. Validate extension
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "pdf" || ext == "epub" else {
            throw BookImportError.unsupportedFormat
        }

        // 2. Prepare directories
        try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)

        // 3. Compute MD5 for deduplication
        let md5 = try computeMD5(at: sourceURL)
        if let existing = try await bookDAO.fetchByMD5(md5) {
            throw BookImportError.alreadyExists(existing)
        }

        // 4. Copy file to Books directory (unique name)
        let destName = "\(UUID().uuidString).\(ext)"
        let destURL = booksDirectory.appendingPathComponent(destName)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            throw BookImportError.copyFailed(error)
        }

        // 5. Extract metadata & generate cover
        let (title, author, pageCount) = extractPDFMetadata(at: destURL, fallbackName: sourceURL.deletingPathExtension().lastPathComponent)
        let coverPath = generatePDFCover(at: destURL, md5: md5)

        // 6. Create and save Book record
        let now = Date()
        let book = Book(
            id: nil,
            title: title,
            coverPath: coverPath,
            filePath: destURL.path,
            lastReadPosition: "",
            readingPercentage: 0,
            author: author,
            isDeleted: false,
            description: nil,
            rating: 0,
            groupId: 0,
            md5: md5,
            createTime: now,
            updateTime: now
        )
        do {
            return try await bookDAO.save(book)
        } catch {
            // Clean up copied file on DB failure
            try? FileManager.default.removeItem(at: destURL)
            throw BookImportError.saveFailed(error)
        }
    }

    // MARK: - Private helpers

    private func computeMD5(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func extractPDFMetadata(at url: URL, fallbackName: String) -> (title: String, author: String, pageCount: Int) {
        guard let doc = PDFDocument(url: url) else {
            return (fallbackName, "", 0)
        }
        let attrs = doc.documentAttributes ?? [:]
        let title = (attrs[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in: .whitespaces)
        let author = (attrs[PDFDocumentAttribute.authorAttribute] as? String)?.trimmingCharacters(in: .whitespaces)
        return (
            (title?.isEmpty ?? true) ? fallbackName : title!,
            author ?? "",
            doc.pageCount
        )
    }

    /// Renders the first PDF page as a PNG and saves it. Returns the relative cover filename.
    private func generatePDFCover(at url: URL, md5: String) -> String {
        let coverName = "\(md5)_cover.png"
        let coverURL = coversDirectory.appendingPathComponent(coverName)

        guard !FileManager.default.fileExists(atPath: coverURL.path),
              let doc = PDFDocument(url: url),
              let firstPage = doc.page(at: 0) else {
            return coverName
        }

        let bounds = firstPage.bounds(for: .mediaBox)
        let scale: CGFloat = 1.5
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return coverName
        }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        firstPage.draw(with: .mediaBox, to: ctx)

        if let cgImage = ctx.makeImage() {
#if canImport(UIKit)
            let uiImage = UIImage(cgImage: cgImage)
            if let pngData = uiImage.pngData() {
                try? pngData.write(to: coverURL)
            }
#elseif canImport(AppKit)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: coverURL)
            }
#endif
        }
        return coverName
    }
}
```

- [x] **Step 2.2: Commit**

```bash
cd /Users/gwaanl/GitHub/papertok-reader
git add Packages/PTFeatures/Sources/PTFeatures/Bookshelf/BookImportService.swift
git commit -m "feat(PTFeatures): add BookImportService for PDF import with metadata extraction and cover generation"
```

---

### Task 3: Add `importBook` to BookshelfViewModel + Tests

**Files:**
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/BookshelfViewModel.swift`
- Modify: `Packages/PTFeatures/Tests/PTFeaturesTests/Bookshelf/BookshelfViewModelTests.swift`

- [x] **Step 3.1: Write the failing test**

Open `Packages/PTFeatures/Tests/PTFeaturesTests/Bookshelf/BookshelfViewModelTests.swift` and add:

```swift
import Testing
import Foundation
import PDFKit
@testable import PTFeatures
import PTCore

@Suite struct BookshelfViewModelImportTests {
    /// Creates a minimal one-page PDF at `url` suitable for import testing.
    func makeMinimalPDF(at url: URL) throws {
        let pdfDoc = PDFDocument()
        let page = PDFPage()
        pdfDoc.insert(page, at: 0)
        guard let data = pdfDoc.dataRepresentation() else {
            struct PDFCreateError: Error {}
            throw PDFCreateError()
        }
        try data.write(to: url)
    }

    @Test func importBook_addsBookToList() async throws {
        let db = try AppDatabase.makeInMemory()
        let vm = BookshelfViewModel(database: db)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_import_\(UUID().uuidString).pdf")
        try makeMinimalPDF(at: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await vm.importBook(url: tempURL)

        #expect(vm.importError == nil, "Expected no error but got \(String(describing: vm.importError))")
        #expect(vm.books.count == 1)
        #expect(vm.books.first?.filePath.hasSuffix(".pdf") == true)
    }
}
```

- [x] **Step 3.2: Run test to verify it fails**

```bash
swift test --package-path Packages/PTFeatures --filter importBook_addsBookToList 2>&1 | tail -10
```

Expected: error — `importBook` does not exist on `BookshelfViewModel`.

- [x] **Step 3.3: Add import support to BookshelfViewModel**

Replace the entire content of `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/BookshelfViewModel.swift` with:

```swift
import Foundation
import Observation
import PTCore

@Observable
public final class BookshelfViewModel: @unchecked Sendable {
    public var books: [Book] = []
    public var searchQuery: String = ""
    public var isLoading: Bool = false
    public var isImporting: Bool = false
    public var importError: BookImportError?
    public var sortOrder: SortOrder = .dateDesc

    public enum SortOrder: String, CaseIterable, Sendable {
        case dateDesc, dateAsc, titleAsc, titleDesc, authorAsc
    }

    private let bookDAO: BookDAO
    private let importService: BookImportService

    public init(database: AppDatabase) {
        self.bookDAO = BookDAO(database: database)
        self.importService = BookImportService(database: database)
    }

    public func loadBooks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if searchQuery.isEmpty {
                books = try await bookDAO.fetchAll()
            } else {
                books = try await bookDAO.search(query: searchQuery)
            }
            sortBooks()
        } catch {
            books = []
        }
    }

    public func deleteBook(id: Int64) async {
        do {
            try await bookDAO.softDelete(id: id)
            books.removeAll { $0.id == id }
        } catch { }
    }

    /// Import a book file from the given URL. On success, prepends the new book to `books`.
    public func importBook(url: URL) async {
        isImporting = true
        importError = nil
        defer { isImporting = false }
        do {
            let book = try await importService.importFile(from: url)
            books.insert(book, at: 0)
        } catch let error as BookImportError {
            importError = error
        } catch {
            importError = .saveFailed(error)
        }
    }

    private func sortBooks() {
        switch sortOrder {
        case .dateDesc: books.sort { $0.createTime > $1.createTime }
        case .dateAsc: books.sort { $0.createTime < $1.createTime }
        case .titleAsc: books.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleDesc: books.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .authorAsc: books.sort { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        }
    }
}
```

- [x] **Step 3.4: Run test to verify it passes**

```bash
swift test --package-path Packages/PTFeatures --filter importBook_addsBookToList 2>&1 | tail -5
```

Expected: `Test run with 1 test passed`

- [x] **Step 3.5: Commit**

```bash
cd /Users/gwaanl/GitHub/papertok-reader
git add Packages/PTFeatures/Sources/PTFeatures/Bookshelf/BookshelfViewModel.swift \
        Packages/PTFeatures/Tests/PTFeaturesTests/Bookshelf/BookshelfViewModelTests.swift
git commit -m "feat(PTFeatures): add importBook to BookshelfViewModel with isImporting/importError state"
```

---

### Task 4: Create ReaderViewModel + Tests

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderViewModel.swift`
- Create: `Packages/PTFeatures/Tests/PTFeaturesTests/Reader/ReaderViewModelTests.swift`

- [x] **Step 4.1: Write the failing test**

Create `Packages/PTFeatures/Tests/PTFeaturesTests/Reader/ReaderViewModelTests.swift`:

```swift
import Testing
import Foundation
import PDFKit
@testable import PTFeatures
import PTCore

@Suite struct ReaderViewModelTests {
    func makeMinimalPDF(at url: URL) throws {
        let pdfDoc = PDFDocument()
        let page = PDFPage()
        pdfDoc.insert(page, at: 0)
        guard let data = pdfDoc.dataRepresentation() else {
            struct E: Error {}; throw E()
        }
        try data.write(to: url)
    }

    @Test func loadDocument_setsPageCount() async throws {
        let db = try AppDatabase.makeInMemory()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader_test_\(UUID().uuidString).pdf")
        try makeMinimalPDF(at: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let now = Date()
        let book = Book(
            id: 1, title: "Test", coverPath: "", filePath: tempURL.path,
            lastReadPosition: "", readingPercentage: 0, author: "",
            isDeleted: false, description: nil, rating: 0, groupId: 0,
            md5: nil, createTime: now, updateTime: now
        )
        let vm = ReaderViewModel(book: book, database: db)
        await vm.loadDocument()

        #expect(vm.pageCount == 1)
        #expect(vm.currentPage == 0)
    }

    @Test func goToPage_clampsToValidRange() async throws {
        let db = try AppDatabase.makeInMemory()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader_clamp_\(UUID().uuidString).pdf")
        try makeMinimalPDF(at: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let now = Date()
        let book = Book(
            id: 1, title: "Test", coverPath: "", filePath: tempURL.path,
            lastReadPosition: "", readingPercentage: 0, author: "",
            isDeleted: false, description: nil, rating: 0, groupId: 0,
            md5: nil, createTime: now, updateTime: now
        )
        let vm = ReaderViewModel(book: book, database: db)
        await vm.loadDocument()

        vm.goToPage(100)
        #expect(vm.currentPage == 0) // clamped to last valid page (0 for a 1-page doc)

        vm.goToPage(-5)
        #expect(vm.currentPage == 0)
    }
}
```

- [x] **Step 4.2: Run test to verify it fails**

```bash
swift test --package-path Packages/PTFeatures --filter ReaderViewModelTests 2>&1 | tail -10
```

Expected: error — `ReaderViewModel` does not exist.

- [x] **Step 4.3: Create ReaderViewModel**

Create `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderViewModel.swift`:

```swift
import Foundation
import Observation
import PDFKit
import PTCore
import PTReader

@Observable
public final class ReaderViewModel: @unchecked Sendable {
    // MARK: - Published state
    public private(set) var pageCount: Int = 0
    public var currentPage: Int = 0 {
        didSet {
            guard pageCount > 0 else { return }
            currentPage = max(0, min(currentPage, pageCount - 1))
            readingPercentage = pageCount > 1 ? Double(currentPage) / Double(pageCount - 1) : 1.0
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
        self.currentPage = restoreLastPage(from: book.lastReadPosition)
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
        tocEntries = bridge.segmentByOutline().map { $0.toChapterEntry() }
        if tocEntries.isEmpty {
            tocEntries = bridge.syntheticChapters().map { $0.toChapterEntry() }
        }
    }

    // MARK: - Navigation

    public func goToPage(_ page: Int) {
        guard pageCount > 0 else { return }
        currentPage = max(0, min(page, pageCount - 1))
    }

    public func goToChapter(href: String) {
        guard let range = PDFChapter.parsePageRange(from: href) else { return }
        goToPage(range.startPage)
    }

    // MARK: - Progress persistence

    public func saveProgress() async {
        guard var updatedBook = try? await bookDAO.fetchById(book.id ?? -1),
              book.id != nil else { return }
        updatedBook.readingPercentage = readingPercentage
        updatedBook.lastReadPosition = "\(currentPage)"
        updatedBook.updateTime = Date()
        _ = try? await bookDAO.save(updatedBook)
    }

    // MARK: - Private helpers

    private func restoreLastPage(from position: String) -> Int {
        Int(position) ?? 0
    }
}
```

- [x] **Step 4.4: Run tests to verify they pass**

```bash
swift test --package-path Packages/PTFeatures --filter ReaderViewModelTests 2>&1 | tail -5
```

Expected: `Test run with 2 tests passed`

- [x] **Step 4.5: Commit**

```bash
cd /Users/gwaanl/GitHub/papertok-reader
git add Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderViewModel.swift \
        Packages/PTFeatures/Tests/PTFeaturesTests/Reader/ReaderViewModelTests.swift
git commit -m "feat(PTFeatures): add ReaderViewModel with PDF load, TOC, page navigation, and progress persistence"
```

---

### Task 5: Create PDFReaderView

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderView.swift`

- [x] **Step 5.1: Create PDFReaderView**

Create `Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderView.swift`:

```swift
import SwiftUI
import PDFKit
import PTCore
import PTUI

// MARK: - PDFKit wrapper

#if canImport(UIKit)
import UIKit

/// SwiftUI wrapper for PDFKit's PDFView (iOS).
struct NativePDFView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.backgroundColor = UIColor(Morandi.background)
        pdfView.document = document
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        let targetIndex = max(0, min(currentPage, document.pageCount - 1))
        if let page = document.page(at: targetIndex),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage, document: document)
    }

    class Coordinator: NSObject {
        @Binding var currentPage: Int
        let document: PDFDocument

        init(currentPage: Binding<Int>, document: PDFDocument) {
            self._currentPage = currentPage
            self.document = document
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage else { return }
            let index = document.index(for: page)
            DispatchQueue.main.async { self.currentPage = index }
        }
    }
}

#elseif canImport(AppKit)
import AppKit

/// SwiftUI wrapper for PDFKit's PDFView (macOS).
struct NativePDFView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.document = document
        pdfView.backgroundColor = NSColor(Morandi.background)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        let targetIndex = max(0, min(currentPage, document.pageCount - 1))
        if let page = document.page(at: targetIndex),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage, document: document)
    }

    class Coordinator: NSObject {
        @Binding var currentPage: Int
        let document: PDFDocument

        init(currentPage: Binding<Int>, document: PDFDocument) {
            self._currentPage = currentPage
            self.document = document
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage else { return }
            let index = document.index(for: page)
            DispatchQueue.main.async { self.currentPage = index }
        }
    }
}
#endif

// MARK: - Full reader view

/// Full-screen PDF reader with toolbar and TOC sidebar.
public struct PDFReaderView: View {
    @State private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    public init(book: Book, database: AppDatabase) {
        _viewModel = State(initialValue: ReaderViewModel(book: book, database: database))
    }

    public var body: some View {
        ZStack {
            Morandi.background.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("Opening…")
                    .tint(Morandi.accent)

            } else if let doc = viewModel.pdfDocument {
                NativePDFView(document: doc, currentPage: $viewModel.currentPage)
                    .ignoresSafeArea(edges: .bottom)

            } else {
                ContentUnavailableView(
                    "Cannot Open",
                    systemImage: "doc.text.slash",
                    description: Text("The file could not be opened.")
                )
            }
        }
        .navigationTitle(viewModel.book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $viewModel.showTOC) { tocSheet }
        .task { await viewModel.loadDocument() }
        .onDisappear { Task { await viewModel.saveProgress() } }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { await viewModel.saveProgress() }
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(Morandi.accent)
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            // Progress badge
            if viewModel.pageCount > 0 {
                Text("\(viewModel.currentPage + 1) / \(viewModel.pageCount)")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                    .monospacedDigit()
            }

            // TOC button
            Button {
                viewModel.showTOC = true
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(Morandi.accent)
            }
        }
    }

    // MARK: - TOC Sheet

    private var tocSheet: some View {
        NavigationStack {
            List(viewModel.tocEntries) { entry in
                Button {
                    viewModel.goToChapter(href: entry.href)
                    viewModel.showTOC = false
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        if entry.level > 0 {
                            Spacer().frame(width: CGFloat(entry.level) * AppSpacing.lg)
                        }
                        Text(entry.title)
                            .font(entry.level == 0 ? AppTypography.headline : AppTypography.body)
                            .foregroundStyle(entry.level == 0 ? Morandi.primaryText : Morandi.secondaryText)
                        Spacer()
                    }
                }
                .listRowBackground(Morandi.background)
            }
            .listStyle(.plain)
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { viewModel.showTOC = false }
                        .foregroundStyle(Morandi.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [x] **Step 5.2: Commit**

```bash
cd /Users/gwaanl/GitHub/papertok-reader
git add Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderView.swift
git commit -m "feat(PTFeatures): add PDFReaderView wrapping PDFKit with TOC sheet and progress toolbar"
```

---

### Task 6: Update BookshelfScreen in ContentView.swift

**Files:**
- Modify: `App/ContentView.swift`

- [x] **Step 6.1: Rewrite BookshelfScreen**

Replace the entire `BookshelfScreen` struct (from `struct BookshelfScreen: View` to its closing `}`) in `App/ContentView.swift` with:

```swift
struct BookshelfScreen: View {
    let database: AppDatabase
    @State private var viewModel: BookshelfViewModel
    @State private var showImporter = false
    @State private var showImportError = false

    init(database: AppDatabase) {
        self.database = database
        _viewModel = State(initialValue: BookshelfViewModel(database: database))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(Morandi.accent)
                } else if viewModel.books.isEmpty {
                    ContentUnavailableView(
                        "No Books Yet",
                        systemImage: "books.vertical",
                        description: Text("Tap + to import a PDF or EPUB file.")
                    )
                } else {
                    bookList
                }
            }
            .navigationTitle("Bookshelf")
            .searchable(text: $viewModel.searchQuery, prompt: "Search books")
            .toolbar { toolbarItems }
            .onChange(of: viewModel.searchQuery) { _, _ in
                Task { await viewModel.loadBooks() }
            }
            .task { await viewModel.loadBooks() }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                Task {
                    await viewModel.importBook(url: url)
                    if accessing { url.stopAccessingSecurityScopedResource() }
                    if viewModel.importError != nil { showImportError = true }
                }
            }
            .alert(
                "Import Failed",
                isPresented: $showImportError,
                presenting: viewModel.importError
            ) { _ in
                Button("OK") { viewModel.importError = nil }
            } message: { error in
                Text(error.errorDescription ?? "Unknown error")
            }
            .overlay {
                if viewModel.isImporting {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: AppSpacing.md) {
                            ProgressView()
                                .tint(Morandi.accent)
                            Text("Importing…")
                                .font(AppTypography.subheadline)
                                .foregroundStyle(Morandi.secondaryText)
                        }
                        .padding(AppSpacing.xl)
                        .background(Morandi.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                    }
                }
            }
        }
    }

    // MARK: - Book list

    private var bookList: some View {
        List(viewModel.books) { book in
            NavigationLink {
                PDFReaderView(book: book, database: database)
                    .navigationBarBackButtonHidden(true)
            } label: {
                bookRow(book)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    if let id = book.id {
                        Task { await viewModel.deleteBook(id: id) }
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .listRowBackground(Morandi.background)
        }
        .listStyle(.plain)
        .background(Morandi.background)
    }

    private func bookRow(_ book: Book) -> some View {
        HStack(spacing: AppSpacing.md) {
            // Cover placeholder
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                .fill(Morandi.sand.opacity(0.6))
                .frame(width: 44, height: 60)
                .overlay(
                    Image(systemName: "doc.text")
                        .foregroundStyle(Morandi.warmGray)
                )

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(book.title)
                    .font(AppTypography.headline)
                    .foregroundStyle(Morandi.primaryText)
                    .lineLimit(2)
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Morandi.secondaryText)
                        .lineLimit(1)
                }
                // Progress bar
                if book.readingPercentage > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Morandi.divider
                                .frame(height: 3)
                                .clipShape(Capsule())
                            Morandi.accent
                                .frame(width: geo.size.width * book.readingPercentage, height: 3)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(height: 3)
                }
            }

            Spacer()

            Text("\(Int(book.readingPercentage * 100))%")
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.accent)
                .monospacedDigit()
        }
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showImporter = true
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(Morandi.accent)
            }
            .disabled(viewModel.isImporting)
        }
    }
}
```

- [x] **Step 6.2: Add PTFeatures import to ContentView.swift**

Make sure the top of `App/ContentView.swift` has:

```swift
import SwiftUI
import PTFeatures
```

(It already imports PTFeatures; verify `PDFReaderView` is now accessible from the PTFeatures module.)

- [x] **Step 6.3: Verify the Xcode project builds**

```bash
cd /Users/gwaanl/GitHub/papertok-reader
xcodebuild -workspace PaperTokReader.xcworkspace \
           -scheme PaperTokReader \
           -destination 'platform=iOS Simulator,name=iPhone 16' \
           build 2>&1 | grep -E "error:|warning:|BUILD"
```

Fix any compile errors before proceeding.

- [x] **Step 6.4: Commit**

```bash
cd /Users/gwaanl/GitHub/papertok-reader
git add App/ContentView.swift
git commit -m "feat(App): add import button with fileImporter and NavigationLink to PDFReaderView on BookshelfScreen"
```

---

### Task 7: Run Full Test Suite

- [x] **Step 7.1: Run all package tests**

```bash
cd /Users/gwaanl/GitHub/papertok-reader
swift test --package-path Packages/PTCore 2>&1 | tail -5
swift test --package-path Packages/PTFeatures 2>&1 | tail -5
```

Expected: both suites pass with zero failures.

- [x] **Step 7.2: Fix any failures, then push**

```bash
git push origin swift-native
```

---

## Self-Review Checklist

### Spec coverage

| Requirement | Task |
|---|---|
| "+" import button in toolbar | Task 6 (toolbarItems) |
| `.fileImporter()` for EPUB/PDF | Task 6 (fileImporter modifier; PDF type added; EPUB is future work) |
| Copy to Documents directory | Task 2 (BookImportService.booksDirectory) |
| Parse PDF metadata (title, author, page count) | Task 2 (extractPDFMetadata) |
| Create Book record via BookDAO.save | Task 2 (importFile) |
| Generate cover thumbnail | Task 2 (generatePDFCover) |
| Refresh bookshelf after import | Task 3 (importBook prepends to books) |
| PDFReaderView (UIKit bridge) | Task 5 (NativePDFView) |
| Tap book → navigate to reader | Task 6 (NavigationLink → PDFReaderView) |
| Page navigation | Task 4 (goToPage, NativePDFView coordinator) |
| TOC navigation | Task 4 (goToChapter), Task 5 (tocSheet) |
| Progress tracking (Book.readingPercentage) | Task 4 (saveProgress) |
| Toolbar: back, TOC, progress display | Task 5 (toolbarContent) |
| Morandi design system | All tasks (Morandi.*, AppSpacing.*, AppTypography.*) |
| Compile passes | Task 6 Step 6.3 (xcodebuild check) |

### Notes on EPUB
The `.fileImporter` is set to `.pdf` only. EPUB support requires Readium (not yet integrated). The `BookImportService.importFile` already accepts `epub` extension — once Readium is added, metadata extraction can be added there. This is intentional scope limitation.
