import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite)
import CSQLite
#endif

/// Full-text search index service using SQLite FTS5.
///
/// Creates and queries an FTS5 virtual table for book content,
/// enabling semantic-style search across the user's library.
public final class RAGIndexService: Sendable {
    private let dbPath: String
    private let queue: DispatchQueue

    public init(databasePath: String) {
        self.dbPath = databasePath
        self.queue = DispatchQueue(label: "ai.papertok.rag-index", qos: .userInitiated)
    }

    /// Convenience initializer using the standard App Support directory.
    public convenience init(directory: URL) {
        self.init(databasePath: directory.appendingPathComponent("ai_index.db").path)
    }

    // MARK: - Index Management

    /// Create the FTS5 virtual table if it does not exist.
    public func createIndex() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [dbPath] in
                do {
                    let db = try SQLiteConnection(path: dbPath)
                    try db.execute("""
                        CREATE VIRTUAL TABLE IF NOT EXISTS book_fts USING fts5(
                            book_id UNINDEXED,
                            chapter_href UNINDEXED,
                            chapter_title,
                            content,
                            tokenize='porter unicode61'
                        );
                    """)
                    // Metadata table for tracking indexed books
                    try db.execute("""
                        CREATE TABLE IF NOT EXISTS index_metadata (
                            book_id INTEGER PRIMARY KEY,
                            indexed_at TEXT NOT NULL,
                            chapter_count INTEGER NOT NULL DEFAULT 0
                        );
                    """)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Index a single book's content. Replaces any existing index for this book.
    public func indexBook(bookId: Int64, chapters: [ChapterContent]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [dbPath] in
                do {
                    let db = try SQLiteConnection(path: dbPath)
                    // Remove old entries for this book
                    try db.execute("DELETE FROM book_fts WHERE book_id = ?", parameters: [.integer(bookId)])
                    try db.execute("DELETE FROM index_metadata WHERE book_id = ?", parameters: [.integer(bookId)])

                    // Insert chapters
                    for chapter in chapters {
                        try db.execute(
                            "INSERT INTO book_fts (book_id, chapter_href, chapter_title, content) VALUES (?, ?, ?, ?)",
                            parameters: [
                                .integer(bookId),
                                .text(chapter.href),
                                .text(chapter.title),
                                .text(chapter.textContent),
                            ]
                        )
                    }

                    // Update metadata
                    let iso = ISO8601DateFormatter().string(from: Date())
                    try db.execute(
                        "INSERT OR REPLACE INTO index_metadata (book_id, indexed_at, chapter_count) VALUES (?, ?, ?)",
                        parameters: [.integer(bookId), .text(iso), .integer(Int64(chapters.count))]
                    )

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Search indexed content across the library.
    public func search(query: String, bookId: Int64? = nil, limit: Int = 20) async throws -> [SearchResult] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[SearchResult], Error>) in
            queue.async { [dbPath] in
                do {
                    let db = try SQLiteConnection(path: dbPath)
                    var sql = """
                        SELECT book_id, chapter_href, chapter_title,
                               snippet(book_fts, 3, '<b>', '</b>', '...', 40) AS snippet,
                               rank
                        FROM book_fts
                        WHERE book_fts MATCH ?
                    """
                    var params: [SQLiteConnection.SQLiteValue] = [.text(query)]

                    if let bookId {
                        sql += " AND book_id = ?"
                        params.append(.integer(bookId))
                    }

                    sql += " ORDER BY rank LIMIT ?"
                    params.append(.integer(Int64(limit)))

                    let rows = try db.query(sql, parameters: params)
                    let results = rows.map { row in
                        SearchResult(
                            bookId: row["book_id"] as? Int64 ?? 0,
                            chapterHref: row["chapter_href"] as? String ?? "",
                            chapterTitle: row["chapter_title"] as? String ?? "",
                            snippet: row["snippet"] as? String ?? "",
                            rank: row["rank"] as? Double ?? 0
                        )
                    }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Index a book and additionally compute and store embeddings for provided chunks.
    ///
    /// This complements `indexBook(bookId:chapters:)` (which populates the FTS5
    /// table) by also populating a `VectorStore` with embeddings, enabling
    /// hybrid FTS + vector search.
    public func indexBookWithEmbeddings(
        bookId: Int64,
        chunks: [TextChunk],
        vectorStore: VectorStore,
        embedding: EmbeddingService
    ) async throws {
        guard !chunks.isEmpty else { return }
        let vectors = try await embedding.embedBatch(chunks.map { $0.text })
        try await vectorStore.removeBook(bookId: bookId)
        try await vectorStore.store(chunks: chunks, embeddings: vectors, bookId: bookId)
    }

    /// Check whether a book has been indexed.
    public func isBookIndexed(bookId: Int64) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            queue.async { [dbPath] in
                do {
                    let db = try SQLiteConnection(path: dbPath)
                    let rows = try db.query(
                        "SELECT book_id FROM index_metadata WHERE book_id = ?",
                        parameters: [.integer(bookId)]
                    )
                    continuation.resume(returning: !rows.isEmpty)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Remove a book's index.
    public func removeIndex(bookId: Int64) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [dbPath] in
                do {
                    let db = try SQLiteConnection(path: dbPath)
                    try db.execute("DELETE FROM book_fts WHERE book_id = ?", parameters: [.integer(bookId)])
                    try db.execute("DELETE FROM index_metadata WHERE book_id = ?", parameters: [.integer(bookId)])
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Types

    public struct ChapterContent: Sendable {
        public let href: String
        public let title: String
        public let textContent: String

        public init(href: String, title: String, textContent: String) {
            self.href = href
            self.title = title
            self.textContent = textContent
        }
    }

    public struct SearchResult: Sendable {
        public let bookId: Int64
        public let chapterHref: String
        public let chapterTitle: String
        public let snippet: String
        public let rank: Double
    }
}

// MARK: - Minimal SQLite Wrapper

/// Minimal SQLite wrapper for FTS5 operations.
/// This avoids pulling in GRDB at the PTAIServices layer.
internal final class SQLiteConnection: @unchecked Sendable {
    private var db: OpaquePointer?

    enum SQLiteValue {
        case integer(Int64)
        case text(String)
        case real(Double)
        case blob(Data)
        case null
    }

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw RAGIndexError.sqliteError(msg)
        }
        self.db = handle
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String, parameters: [SQLiteValue] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RAGIndexError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt: stmt!, parameters: parameters)
        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw RAGIndexError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
    }

    func query(_ sql: String, parameters: [SQLiteValue] = []) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RAGIndexError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt: stmt!, parameters: parameters)

        var rows: [[String: Any]] = []
        let columnCount = sqlite3_column_count(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    row[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_BLOB:
                    let byteCount = Int(sqlite3_column_bytes(stmt, i))
                    if byteCount > 0, let bytes = sqlite3_column_blob(stmt, i) {
                        row[name] = Data(bytes: bytes, count: byteCount)
                    } else {
                        row[name] = Data()
                    }
                default:
                    row[name] = nil as Any?
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func bind(stmt: OpaquePointer, parameters: [SQLiteValue]) throws {
        for (index, param) in parameters.enumerated() {
            let idx = Int32(index + 1)
            let result: Int32
            switch param {
            case .integer(let v): result = sqlite3_bind_int64(stmt, idx, v)
            case .text(let v): result = sqlite3_bind_text(stmt, idx, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .real(let v): result = sqlite3_bind_double(stmt, idx, v)
            case .blob(let data):
                result = data.withUnsafeBytes { raw -> Int32 in
                    let count = Int32(data.count)
                    if let base = raw.baseAddress, count > 0 {
                        return sqlite3_bind_blob(stmt, idx, base, count, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    } else {
                        return sqlite3_bind_zeroblob(stmt, idx, 0)
                    }
                }
            case .null: result = sqlite3_bind_null(stmt, idx)
            }
            guard result == SQLITE_OK else {
                throw RAGIndexError.sqliteError("bind error at index \(index)")
            }
        }
    }
}

public enum RAGIndexError: LocalizedError {
    case sqliteError(String)

    public var errorDescription: String? {
        switch self {
        case .sqliteError(let msg): return "RAG index SQLite error: \(msg)"
        }
    }
}
