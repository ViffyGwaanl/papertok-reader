import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite)
import CSQLite
#endif

/// A single search hit from the memory FTS5 index.
public struct MemorySearchResult: Sendable, Equatable {
    public let path: String
    public let snippet: String
    public let date: String
    public let rank: Double

    public init(path: String, snippet: String, date: String, rank: Double) {
        self.path = path
        self.snippet = snippet
        self.date = date
        self.rank = rank
    }
}

/// Full-text search index over markdown memory files, backed by SQLite FTS5.
///
/// Mirrors the pattern used by ``RAGIndexService`` (see `RAG/RAGIndexService.swift`) but
/// operates on files inside the user's memory directory rather than book chapters.
public actor MemoryIndexDatabase {
    public enum IndexError: LocalizedError {
        case fileNotFound(String)
        case sqliteError(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let path): return "Memory file not found: \(path)"
            case .sqliteError(let msg): return "Memory index SQLite error: \(msg)"
            }
        }
    }

    private let dbPath: String
    private var createdIndex = false

    public init(databasePath: String) {
        self.dbPath = databasePath
    }

    /// Convenience initializer: stores the database under `memory_index.db` in the given directory.
    public init(directory: URL) {
        self.dbPath = directory.appendingPathComponent("memory_index.db").path
    }

    // MARK: - Index Management

    public func createIndex() throws {
        if createdIndex { return }
        let db = try SQLiteConnection(path: dbPath)
        try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(
                path,
                content,
                date,
                snippet,
                tokenize='porter unicode61'
            );
        """)
        createdIndex = true
    }

    /// Read a markdown file at `path` and upsert it into the FTS index.
    public func indexFile(path: String) throws {
        try createIndex()
        guard FileManager.default.fileExists(atPath: path) else {
            throw IndexError.fileNotFound(path)
        }
        let url = URL(fileURLWithPath: path)
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let date = Self.extractDate(from: url.lastPathComponent)
        let snippet = String(content.prefix(240))

        let db = try SQLiteConnection(path: dbPath)
        // FTS5 virtual tables support plain DELETE by column match for unindexed path.
        try db.execute("DELETE FROM memory_fts WHERE path = ?", parameters: [.text(path)])
        try db.execute(
            "INSERT INTO memory_fts (path, content, date, snippet) VALUES (?, ?, ?, ?)",
            parameters: [.text(path), .text(content), .text(date), .text(snippet)]
        )
    }

    /// Walk `directory` (non-recursive) and index every `.md` file found.
    @discardableResult
    public func indexAllFiles(in directory: URL) throws -> Int {
        try createIndex()
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return 0 }
        let items = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var count = 0
        for item in items where item.pathExtension.lowercased() == "md" {
            try indexFile(path: item.path)
            count += 1
        }
        return count
    }

    /// Search the index using an FTS5 MATCH query.
    public func search(query: String, limit: Int = 20) throws -> [MemorySearchResult] {
        try createIndex()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let db = try SQLiteConnection(path: dbPath)
        let sql = """
            SELECT path, date,
                   snippet(memory_fts, 1, '<b>', '</b>', '...', 40) AS match_snippet,
                   rank
            FROM memory_fts
            WHERE memory_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        """
        let rows = try db.query(sql, parameters: [.text(trimmed), .integer(Int64(limit))])
        return rows.map { row in
            MemorySearchResult(
                path: row["path"] as? String ?? "",
                snippet: row["match_snippet"] as? String ?? "",
                date: row["date"] as? String ?? "",
                rank: (row["rank"] as? Double) ?? Double(row["rank"] as? Int64 ?? 0)
            )
        }
    }

    /// Remove a file's rows from the index.
    public func removeFile(path: String) throws {
        try createIndex()
        let db = try SQLiteConnection(path: dbPath)
        try db.execute("DELETE FROM memory_fts WHERE path = ?", parameters: [.text(path)])
    }

    /// Count indexed rows. Useful for tests and diagnostics.
    public func indexedCount() throws -> Int {
        try createIndex()
        let db = try SQLiteConnection(path: dbPath)
        let rows = try db.query("SELECT COUNT(*) AS c FROM memory_fts")
        if let row = rows.first, let c = row["c"] as? Int64 { return Int(c) }
        return 0
    }

    // MARK: - Helpers

    /// Pull a `YYYY-MM-DD` prefix out of a filename if present.
    private static func extractDate(from filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        guard stem.count >= 10 else { return "" }
        let prefix = String(stem.prefix(10))
        let chars = Array(prefix)
        let ok = chars.count == 10
            && chars[0].isNumber && chars[1].isNumber && chars[2].isNumber && chars[3].isNumber
            && chars[4] == "-"
            && chars[5].isNumber && chars[6].isNumber
            && chars[7] == "-"
            && chars[8].isNumber && chars[9].isNumber
        return ok ? prefix : ""
    }
}
