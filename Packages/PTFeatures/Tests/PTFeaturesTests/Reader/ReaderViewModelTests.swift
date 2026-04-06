import Testing
import Foundation
import PDFKit
@testable import PTFeatures

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
}
