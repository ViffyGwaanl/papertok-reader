import Foundation
import Testing
@testable import PTAIServices

@Suite("MemoryIndexDatabase")
struct MemoryIndexDatabaseTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-index-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeFile(_ dir: URL, name: String, content: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("indexAllFiles indexes every markdown file in a directory")
    func testIndexAllFiles() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try writeFile(dir, name: "2025-01-01.md", content: "user discussed quantum mechanics and tea")
        _ = try writeFile(dir, name: "2025-01-02.md", content: "notes about espresso preparation")
        _ = try writeFile(dir, name: "MEMORY.md", content: "durable preferences about coffee")
        _ = try writeFile(dir, name: "ignore.txt", content: "should not be indexed")

        let index = MemoryIndexDatabase(directory: dir)
        let count = try await index.indexAllFiles(in: dir)
        #expect(count == 3)
        let total = try await index.indexedCount()
        #expect(total == 3)
    }

    @Test("search returns FTS5 hits ranked by relevance")
    func testSearchReturnsHits() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try writeFile(dir, name: "2025-02-01.md", content: "The user enjoys pour-over coffee in the morning.")
        _ = try writeFile(dir, name: "2025-02-02.md", content: "Unrelated note about hiking trails.")

        let index = MemoryIndexDatabase(directory: dir)
        _ = try await index.indexAllFiles(in: dir)

        let hits = try await index.search(query: "coffee", limit: 10)
        #expect(hits.count == 1)
        #expect(hits.first?.path.hasSuffix("2025-02-01.md") == true)
        #expect(hits.first?.date == "2025-02-01")
        #expect(hits.first?.snippet.lowercased().contains("coffee") == true)

        let empty = try await index.search(query: "spaceship", limit: 10)
        #expect(empty.isEmpty)
    }

    @Test("removeFile deletes rows and re-indexing updates content")
    func testRemoveAndReindex() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = try writeFile(dir, name: "2025-03-01.md", content: "alpha beta gamma")
        let index = MemoryIndexDatabase(directory: dir)
        try await index.indexFile(path: file.path)
        #expect(try await index.indexedCount() == 1)
        #expect(try await index.search(query: "alpha", limit: 5).count == 1)

        try await index.removeFile(path: file.path)
        #expect(try await index.indexedCount() == 0)
        #expect(try await index.search(query: "alpha", limit: 5).isEmpty)

        // Re-index with different content; ensure upsert works (no duplicate rows).
        try "delta epsilon".write(to: file, atomically: true, encoding: .utf8)
        try await index.indexFile(path: file.path)
        try await index.indexFile(path: file.path)
        #expect(try await index.indexedCount() == 1)
        #expect(try await index.search(query: "delta", limit: 5).count == 1)
        #expect(try await index.search(query: "alpha", limit: 5).isEmpty)
    }
}
