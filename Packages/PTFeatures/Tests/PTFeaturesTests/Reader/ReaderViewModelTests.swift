import Testing
import Foundation
import PDFKit
@testable import PTFeatures
import PTAIServices
import PTCore

private func makeMinimalPDF(at url: URL) throws {
    let pdfDoc = PDFDocument()
    pdfDoc.insert(PDFPage(), at: 0)
    guard let data = pdfDoc.dataRepresentation() else {
        struct PDFCreateError: Error {}
        throw PDFCreateError()
    }
    try data.write(to: url)
}

@Suite("ReaderViewModel")
@MainActor
struct ReaderViewModelTests {
    private func makePDF(pageCount: Int, at url: URL) throws {
        let pdfDoc = PDFDocument()
        for _ in 0..<pageCount {
            pdfDoc.insert(PDFPage(), at: pdfDoc.pageCount)
        }
        try pdfDoc.dataRepresentation()!.write(to: url)
    }

    @Test("loadDocument sets pageCount and currentPage")
    func loadDocumentSetsPageCount() async throws {
        let db = try AppDatabase.makeInMemory()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader_test_\(UUID().uuidString).pdf")
        try makeMinimalPDF(at: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var book = Book.placeholder(title: "Test", filePath: tempURL.path)
        book.id = 1
        let vm = ReaderViewModel(book: book, database: db)
        await vm.loadDocument()

        #expect(vm.pageCount == 1)
        #expect(vm.currentPage == 0)
    }

    @Test("goToPage clamps to valid range")
    func goToPageClampsRange() async throws {
        let db = try AppDatabase.makeInMemory()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader_clamp_\(UUID().uuidString).pdf")
        try makeMinimalPDF(at: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var book = Book.placeholder(title: "Test", filePath: tempURL.path)
        book.id = 1
        let vm = ReaderViewModel(book: book, database: db)
        await vm.loadDocument()

        vm.goToPage(100)
        #expect(vm.currentPage == 0) // 1-page doc, clamped to 0

        vm.goToPage(-5)
        #expect(vm.currentPage == 0)
    }

    @Test("restores last read page from book position")
    func restoresLastPage() async throws {
        let db = try AppDatabase.makeInMemory()

        // Create a 3-page PDF
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader_restore_\(UUID().uuidString).pdf")
        let pdfDoc = PDFDocument()
        for _ in 0..<3 { pdfDoc.insert(PDFPage(), at: pdfDoc.pageCount) }
        try pdfDoc.dataRepresentation()!.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var book = Book.placeholder(title: "Test", filePath: tempURL.path)
        book.id = 1
        book.lastReadPosition = "2"
        let vm = ReaderViewModel(book: book, database: db)
        await vm.loadDocument()

        #expect(vm.currentPage == 2)
    }

    @Test("loadDocument publishes an active PDF reader session shell")
    func loadDocumentPublishesReaderSession() async throws {
        let db = try AppDatabase.makeInMemory()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader_session_\(UUID().uuidString).pdf")
        try makeMinimalPDF(at: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var book = Book.placeholder(title: "Test", filePath: tempURL.path)
        book.id = 11
        let readerSessionStore = ReaderSessionContextStore()
        let vm = ReaderViewModel(book: book, database: db, readerSessionStore: readerSessionStore)

        await vm.loadDocument()

        #expect(readerSessionStore.activeBookId == 11)
        #expect(readerSessionStore.locationHref == "pages:0-0")
        #expect(readerSessionStore.chapterTitle == "Pages 1–1")
        #expect(readerSessionStore.hasBookContentBridge)
    }

    @Test("goToPage updates the shared PDF reader session location")
    func goToPageUpdatesReaderSessionLocation() async throws {
        let db = try AppDatabase.makeInMemory()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader_session_page_\(UUID().uuidString).pdf")
        try makePDF(pageCount: 25, at: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var book = Book.placeholder(title: "Test", filePath: tempURL.path)
        book.id = 12
        let readerSessionStore = ReaderSessionContextStore()
        let vm = ReaderViewModel(book: book, database: db, readerSessionStore: readerSessionStore)

        await vm.loadDocument()
        vm.goToPage(22)

        #expect(readerSessionStore.locationHref == "pages:20-24")
        #expect(readerSessionStore.chapterTitle == "Pages 21–25")
    }

    @Test("loadDocument exposes the PDF content bridge for reader controls")
    func loadDocumentExposesContentBridge() async throws {
        let db = try AppDatabase.makeInMemory()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader_bridge_\(UUID().uuidString).pdf")
        try makeMinimalPDF(at: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var book = Book.placeholder(title: "Test", filePath: tempURL.path)
        book.id = 13
        let vm = ReaderViewModel(book: book, database: db)

        await vm.loadDocument()

        let bridge = try #require(vm.contentBridge)
        let toc = try await bridge.tableOfContents
        #expect(toc.isEmpty == false)
    }

    @Test("localizedPageLabel uses the catalog-backed page format")
    func localizedPageLabelUsesCatalogFormat() {
        #expect(
            ReaderViewModel.localizedPageLabel(for: 2)
                == localizedCatalogFormat("reader.page_number_format", 3)
        )
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
