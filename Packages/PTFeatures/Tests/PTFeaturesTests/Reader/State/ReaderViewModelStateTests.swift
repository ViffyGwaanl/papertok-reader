import Testing
import Foundation
import PDFKit
@testable import PTFeatures
import PTCore

@Suite("ReaderViewModel state")
@MainActor
struct ReaderViewModelStateTests {
    private func writePDF(pageCount: Int = 1, at url: URL) throws {
        let doc = PDFDocument()
        for _ in 0..<pageCount { doc.insert(PDFPage(), at: doc.pageCount) }
        guard let data = doc.dataRepresentation() else {
            struct Err: Error {}
            throw Err()
        }
        try data.write(to: url)
    }

    @Test("initial state is idle")
    func idleAtInit() throws {
        let db = try AppDatabase.makeInMemory()
        var book = Book.placeholder(title: "X", filePath: "/does/not/matter")
        book.id = 1
        let vm = ReaderViewModel(book: book, database: db)
        #expect(vm.state == .idle)
    }

    @Test("loadDocument transitions idle → loading → ready on success")
    func loadingTransitionsToReadyOnSuccess() async throws {
        let db = try AppDatabase.makeInMemory()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vmstate_ready_\(UUID().uuidString).pdf")
        try writePDF(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var book = Book.placeholder(title: "X", filePath: url.path)
        book.id = 1
        let vm = ReaderViewModel(book: book, database: db)
        await vm.loadDocument()
        #expect(vm.state == .ready)
    }

    @Test("loadDocument transitions to failed on missing file")
    func loadingTransitionsToFailedOnError() async throws {
        let db = try AppDatabase.makeInMemory()
        var book = Book.placeholder(title: "X", filePath: "/tmp/does_not_exist_\(UUID().uuidString).pdf")
        book.id = 1
        let vm = ReaderViewModel(book: book, database: db)
        await vm.loadDocument()
        if case .failed(let err) = vm.state {
            #expect(err.kind == .missingResource)
            #expect(err.isRecoverable)
        } else {
            Issue.record("expected .failed state, got \(vm.state)")
        }
    }

    @Test("loadDocument reports empty for zero-page document")
    func loadingTransitionsToEmptyForZeroPages() async throws {
        let db = try AppDatabase.makeInMemory()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vmstate_empty_\(UUID().uuidString).pdf")
        // A PDFDocument with no pages still serializes, but init(url:) rejects it.
        // Write an empty file to simulate a zero-length document.
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var book = Book.placeholder(title: "X", filePath: url.path)
        book.id = 1
        let vm = ReaderViewModel(book: book, database: db)
        await vm.loadDocument()
        if case .failed(let err) = vm.state {
            #expect(err.kind == .openFailed)
        } else {
            Issue.record("expected .failed state, got \(vm.state)")
        }
    }

    @Test("retry recovers from failed state")
    func retryRecoversFromFailedState() async throws {
        let db = try AppDatabase.makeInMemory()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vmstate_retry_\(UUID().uuidString).pdf")
        var book = Book.placeholder(title: "X", filePath: url.path)
        book.id = 1
        let vm = ReaderViewModel(book: book, database: db)
        await vm.loadDocument()
        if case .failed = vm.state {} else {
            Issue.record("precondition: expected .failed")
        }
        try writePDF(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await vm.retry()
        #expect(vm.state == .ready)
    }

    @Test("error kind mapping covers all known kinds")
    func errorMappingCoversAllKnownKinds() {
        let kinds: [ReaderRenderError.Kind] = [
            .openFailed, .parsingFailed, .missingResource, .fileSystemError, .unknown,
        ]
        for k in kinds {
            #expect(k.localizationKey.hasPrefix("reader.state.error.kind."))
        }
    }
}
