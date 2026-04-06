import Foundation
import Testing
@testable import PTAIServices

@Suite("BookshelfLookupTool")
struct BookshelfLookupToolTests {
    @Test("missing database returns error")
    func missingDatabase() async throws {
        let ctx = ToolContext()
        let result = try await BookshelfLookupTool().execute(arguments: [:], context: ctx)
        #expect(result.isError)
        #expect(result.content.contains("Database not available"))
    }

    @Test("with mock database returns results")
    func withMockDatabase() async throws {
        let mock = MockDatabaseAccess()
        let ctx = ToolContext(database: mock)
        let result = try await BookshelfLookupTool().execute(
            arguments: ["query": "test"],
            context: ctx
        )
        #expect(!result.isError)
        #expect(result.content.contains("results"))
    }
}

// MARK: - Mock

struct MockDatabaseAccess: ToolDatabaseAccess {
    func fetchBooks(query: String?, groupId: Int64?, limit: Int) async throws -> [[String: Any]] {
        [["id": 1 as Int64, "title": "Test Book", "author": "Author"]]
    }

    func fetchBookNotes(bookId: Int64?, keyword: String?, limit: Int) async throws -> [[String: Any]] {
        [["id": 1 as Int64, "content": "A test note"]]
    }

    func fetchReadingTime(bookId: Int64?, since: Date?) async throws -> [[String: Any]] {
        [["date": "2026-01-01", "reading_time": 300]]
    }

    func fetchTags() async throws -> [[String: Any]] {
        [["id": 1 as Int64, "name": "Fiction", "color": "#FF0000"]]
    }

    func insertBookNote(_ fields: [String: Any]) async throws {
        // no-op for testing
    }
}
