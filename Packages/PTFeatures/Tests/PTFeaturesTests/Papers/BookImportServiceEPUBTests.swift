import Foundation
import CryptoKit
import Testing
@testable import PTFeatures

@Suite("BookImportService EPUB")
struct BookImportServiceEPUBTests {
    @Test("Importing a real EPUB extracts metadata and cover art")
    func importRealEPUBExtractsMetadataAndCover() async throws {
        let database = try AppDatabase.makeInMemory()
        let libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookImportServiceEPUBTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: libraryRoot) }

        let sourceURL = try #require(sampleEPUBURL())
        let service = BookImportService(database: database, libraryRoot: libraryRoot)
        let book = try await service.importFile(from: sourceURL)

        #expect(book.title == "Children's Literature")
        #expect(book.author == "Charles Madison Curry")
        #expect(book.coverPath.isEmpty == false)

        let coverURL = libraryRoot
            .appendingPathComponent("Covers", isDirectory: true)
            .appendingPathComponent(book.coverPath)
        #expect(FileManager.default.fileExists(atPath: coverURL.path))
    }

    @Test("Importing an EPUB persists it with the EPUB extension")
    func importEPUBPersistsBook() async throws {
        let database = try AppDatabase.makeInMemory()
        let libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookImportServiceEPUBTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: libraryRoot) }

        let sourceURL = libraryRoot.appendingPathComponent("Sample Title.epub")
        try Data("not a real epub but valid import input".utf8).write(to: sourceURL)

        let service = BookImportService(database: database, libraryRoot: libraryRoot)
        let book = try await service.importFile(from: sourceURL)
        let expectedMD5 = Insecure.MD5.hash(data: Data("not a real epub but valid import input".utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        #expect(book.title == "Sample Title")
        #expect(book.filePath.hasSuffix(".epub"))
        #expect(URL(fileURLWithPath: book.filePath).lastPathComponent == "\(expectedMD5).epub")
        #expect(FileManager.default.fileExists(atPath: book.filePath))
    }

    @Test("Importing the same EPUB twice returns alreadyExists")
    func duplicateEPUBReturnsAlreadyExists() async throws {
        let database = try AppDatabase.makeInMemory()
        let libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookImportServiceEPUBTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: libraryRoot) }

        let sourceURL = libraryRoot.appendingPathComponent("Duplicate Title.epub")
        try Data("same epub content".utf8).write(to: sourceURL)

        let service = BookImportService(database: database, libraryRoot: libraryRoot)
        _ = try await service.importFile(from: sourceURL)

        do {
            _ = try await service.importFile(from: sourceURL)
            Issue.record("Expected duplicate EPUB import to throw alreadyExists")
        } catch BookImportError.alreadyExists(let existingBook) {
            #expect(existingBook.title == "Duplicate Title")
        }
    }

    private func sampleEPUBURL(fileID: StaticString = #filePath) -> URL? {
        var packageRoot = URL(fileURLWithPath: "\(fileID)")
        for _ in 0..<4 {
            packageRoot.deleteLastPathComponent()
        }

        let fixtureURL = packageRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("checkouts", isDirectory: true)
            .appendingPathComponent("swift-toolkit", isDirectory: true)
            .appendingPathComponent("Tests", isDirectory: true)
            .appendingPathComponent("Publications", isDirectory: true)
            .appendingPathComponent("Publications", isDirectory: true)
            .appendingPathComponent("childrens-literature.epub")

        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            return nil
        }
        return fixtureURL
    }
}
