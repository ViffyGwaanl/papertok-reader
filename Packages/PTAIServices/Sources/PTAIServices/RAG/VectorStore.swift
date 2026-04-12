import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite)
import CSQLite
#endif

/// A single hit returned by `VectorStore.search`.
public struct VectorSearchResult: Sendable {
    public let chunkText: String
    /// Cosine similarity score in `[-1.0, 1.0]`. Higher is more similar.
    public let score: Float
    public let bookId: Int64
    public let chapter: String?
    public let startOffset: Int

    public init(chunkText: String, score: Float, bookId: Int64, chapter: String?, startOffset: Int) {
        self.chunkText = chunkText
        self.score = score
        self.bookId = bookId
        self.chapter = chapter
        self.startOffset = startOffset
    }
}

/// SQLite-backed vector store with brute-force cosine similarity search.
///
/// Suitable for offline libraries up to a few hundred thousand chunks. For
/// larger corpora, a dedicated ANN index would be needed.
public actor VectorStore {
    private let dbPath: String
    private var initialized = false

    /// Use `":memory:"` as the path for a transient in-memory database (useful for tests).
    public init(databasePath: String) {
        self.dbPath = databasePath
    }

    public init(directory: URL) {
        self.init(databasePath: directory.appendingPathComponent("ai_vectors.db").path)
    }

    // MARK: - Schema

    private func ensureInitialized() throws {
        guard !initialized else { return }
        let db = try SQLiteConnection(path: dbPath)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS vectors (
                id TEXT PRIMARY KEY,
                book_id INTEGER,
                chunk_text TEXT,
                embedding BLOB,
                chapter TEXT,
                start_offset INTEGER,
                created_at INTEGER
            );
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_vectors_book_id ON vectors(book_id);")
        initialized = true
    }

    // MARK: - Public API

    /// Store a list of chunks with their pre-computed embeddings.
    ///
    /// Caller is responsible for producing the embeddings (e.g. via `EmbeddingService`).
    public func store(chunks: [TextChunk], embeddings: [[Float]], bookId: Int64) throws {
        precondition(chunks.count == embeddings.count, "chunks and embeddings must have the same count")
        try ensureInitialized()
        guard !chunks.isEmpty else { return }
        let db = try SQLiteConnection(path: dbPath)
        try db.execute("BEGIN TRANSACTION;")
        do {
            let now = Int64(Date().timeIntervalSince1970)
            for (idx, chunk) in chunks.enumerated() {
                let floats = embeddings[idx]
                let data = Self.dataFromFloats(floats)
                let chapter = chunk.metadata["chapter"] ?? chunk.metadata["chapter_title"]
                try db.execute(
                    "INSERT OR REPLACE INTO vectors (id, book_id, chunk_text, embedding, chapter, start_offset, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    parameters: [
                        .text(chunk.id.uuidString),
                        .integer(bookId),
                        .text(chunk.text),
                        .blob(data),
                        chapter.map { .text($0) } ?? .null,
                        .integer(Int64(chunk.startOffset)),
                        .integer(now),
                    ]
                )
            }
            try db.execute("COMMIT;")
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
    }

    /// Brute-force cosine-similarity search over stored vectors.
    public func search(
        queryEmbedding: [Float],
        limit: Int,
        bookId: Int64? = nil
    ) throws -> [VectorSearchResult] {
        try ensureInitialized()
        guard !queryEmbedding.isEmpty, limit > 0 else { return [] }

        let db = try SQLiteConnection(path: dbPath)
        var sql = "SELECT book_id, chunk_text, embedding, chapter, start_offset FROM vectors"
        var params: [SQLiteConnection.SQLiteValue] = []
        if let bookId {
            sql += " WHERE book_id = ?"
            params.append(.integer(bookId))
        }
        let rows = try db.query(sql, parameters: params)

        let qNorm = Self.norm(queryEmbedding)
        guard qNorm > 0 else { return [] }

        struct Hit {
            let score: Float
            let bookId: Int64
            let text: String
            let chapter: String?
            let startOffset: Int
        }

        var heap: [Hit] = []
        heap.reserveCapacity(min(limit, rows.count))

        for row in rows {
            guard let blob = row["embedding"] as? Data else { continue }
            let vec = Self.floatsFromData(blob)
            guard vec.count == queryEmbedding.count else { continue }
            let score = Self.cosine(queryEmbedding, vec, aNorm: qNorm)
            let hit = Hit(
                score: score,
                bookId: row["book_id"] as? Int64 ?? 0,
                text: row["chunk_text"] as? String ?? "",
                chapter: row["chapter"] as? String,
                startOffset: Int(row["start_offset"] as? Int64 ?? 0)
            )
            // Maintain a simple top-N.
            if heap.count < limit {
                heap.append(hit)
                heap.sort { $0.score > $1.score }
            } else if score > heap.last!.score {
                heap[heap.count - 1] = hit
                heap.sort { $0.score > $1.score }
            }
        }

        return heap.map {
            VectorSearchResult(
                chunkText: $0.text,
                score: $0.score,
                bookId: $0.bookId,
                chapter: $0.chapter,
                startOffset: $0.startOffset
            )
        }
    }

    public func removeBook(bookId: Int64) throws {
        try ensureInitialized()
        let db = try SQLiteConnection(path: dbPath)
        try db.execute("DELETE FROM vectors WHERE book_id = ?", parameters: [.integer(bookId)])
    }

    public func clear() throws {
        try ensureInitialized()
        let db = try SQLiteConnection(path: dbPath)
        try db.execute("DELETE FROM vectors")
    }

    public func count(bookId: Int64? = nil) throws -> Int {
        try ensureInitialized()
        let db = try SQLiteConnection(path: dbPath)
        let sql: String
        var params: [SQLiteConnection.SQLiteValue] = []
        if let bookId {
            sql = "SELECT COUNT(*) AS c FROM vectors WHERE book_id = ?"
            params.append(.integer(bookId))
        } else {
            sql = "SELECT COUNT(*) AS c FROM vectors"
        }
        let rows = try db.query(sql, parameters: params)
        return Int(rows.first?["c"] as? Int64 ?? 0)
    }

    // MARK: - Math / Encoding helpers

    private static func cosine(_ a: [Float], _ b: [Float], aNorm: Float) -> Float {
        var dot: Float = 0
        var bSq: Float = 0
        let n = min(a.count, b.count)
        var i = 0
        while i < n {
            let x = a[i]
            let y = b[i]
            dot += x * y
            bSq += y * y
            i += 1
        }
        let bNorm = bSq.squareRoot()
        guard aNorm > 0, bNorm > 0 else { return 0 }
        return dot / (aNorm * bNorm)
    }

    private static func norm(_ v: [Float]) -> Float {
        var s: Float = 0
        for x in v { s += x * x }
        return s.squareRoot()
    }

    static func dataFromFloats(_ floats: [Float]) -> Data {
        return floats.withUnsafeBufferPointer { ptr in
            Data(buffer: ptr)
        }
    }

    static func floatsFromData(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        return data.withUnsafeBytes { raw -> [Float] in
            let bound = raw.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: bound.baseAddress, count: count))
        }
    }
}
