import Foundation
import Testing
import PTCore
@testable import PaperTokReader

@Suite("FlutterMigrationPlanner")
struct FlutterMigrationPlannerTests {
    @Test("relative legacy book paths are copied and rewritten into absolute current paths")
    func rewritesLegacyRelativeBookPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlutterMigrationPlanner-\(UUID().uuidString)", isDirectory: true)
        let legacyRoot = root.appendingPathComponent("legacy", isDirectory: true)
        let destinationRoot = root.appendingPathComponent("current", isDirectory: true)

        try FileManager.default.createDirectory(at: legacyRoot.appendingPathComponent("file", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyRoot.appendingPathComponent("cover", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyBookURL = legacyRoot.appendingPathComponent("file/book.epub")
        let legacyCoverURL = legacyRoot.appendingPathComponent("cover/book.png")
        try Data("epub".utf8).write(to: legacyBookURL)
        try Data("png".utf8).write(to: legacyCoverURL)

        var book = Book.placeholder(title: "Legacy Book", filePath: "file/book.epub")
        book.coverPath = "cover/book.png"

        let migrated = try FlutterMigrationPlanner.remapBook(
            book,
            legacyRoot: legacyRoot,
            destinationRoot: destinationRoot
        )

        #expect(migrated.filePath == destinationRoot.appendingPathComponent("file/book.epub").path)
        #expect(migrated.coverPath == destinationRoot.appendingPathComponent("cover/book.png").path)
        #expect(FileManager.default.fileExists(atPath: migrated.filePath))
        #expect(FileManager.default.fileExists(atPath: migrated.coverPath))
    }
}
