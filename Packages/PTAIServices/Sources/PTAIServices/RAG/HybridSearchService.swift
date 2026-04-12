import Foundation

/// Where a hybrid search result originated from.
public enum HybridSearchSource: String, Sendable {
    case fts
    case vector
    case both
}

/// A single result returned by `HybridSearchService`.
public struct HybridSearchResult: Sendable {
    public let text: String
    /// Reciprocal-rank-fusion score.
    public let score: Double
    public let source: HybridSearchSource
    public let bookId: Int64
    public let chapter: String?

    public init(text: String, score: Double, source: HybridSearchSource, bookId: Int64, chapter: String?) {
        self.text = text
        self.score = score
        self.source = source
        self.bookId = bookId
        self.chapter = chapter
    }
}

/// Hybrid keyword + vector search that combines `RAGIndexService` (FTS5) and
/// `VectorStore` (brute-force cosine) using Reciprocal Rank Fusion (RRF).
public actor HybridSearchService {
    public let ftsIndex: RAGIndexService
    public let vectorStore: VectorStore
    public let embedding: EmbeddingService

    /// RRF constant; OpenAI / Elastic commonly use 60.
    public let rrfConstant: Double

    public init(
        ftsIndex: RAGIndexService,
        vectorStore: VectorStore,
        embedding: EmbeddingService,
        rrfConstant: Double = 60.0
    ) {
        self.ftsIndex = ftsIndex
        self.vectorStore = vectorStore
        self.embedding = embedding
        self.rrfConstant = rrfConstant
    }

    /// Run a hybrid search using FTS5 keyword match and vector cosine similarity,
    /// combining the two rank lists with Reciprocal Rank Fusion.
    public func search(
        query: String,
        bookId: Int64? = nil,
        limit: Int = 10
    ) async throws -> [HybridSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Run both searches concurrently. Each side asks for more results than
        // the final limit so the fusion step has enough candidates.
        let candidateLimit = max(limit * 4, 20)

        async let ftsTask: [RAGIndexService.SearchResult] = {
            do {
                return try await ftsIndex.search(query: trimmed, bookId: bookId, limit: candidateLimit)
            } catch {
                return []
            }
        }()

        async let vectorTask: [VectorSearchResult] = {
            do {
                let q = try await embedding.embed(trimmed)
                return try await vectorStore.search(queryEmbedding: q, limit: candidateLimit, bookId: bookId)
            } catch {
                return []
            }
        }()

        let ftsResults = await ftsTask
        let vectorResults = await vectorTask

        return fuse(ftsResults: ftsResults, vectorResults: vectorResults, limit: limit)
    }

    // MARK: - Fusion

    private struct Entry {
        var rrfScore: Double
        var text: String
        var bookId: Int64
        var chapter: String?
        var inFTS: Bool
        var inVector: Bool
    }

    private func fuse(
        ftsResults: [RAGIndexService.SearchResult],
        vectorResults: [VectorSearchResult],
        limit: Int
    ) -> [HybridSearchResult] {
        // Keyed by a dedupe key; for FTS results we key on (bookId, chapterHref),
        // for vector results we key on (bookId, startOffset, prefix).
        var table: [String: Entry] = [:]

        for (rank, result) in ftsResults.enumerated() {
            let key = "fts:\(result.bookId):\(result.chapterHref)"
            let contribution = 1.0 / (rrfConstant + Double(rank + 1))
            if var existing = table[key] {
                existing.rrfScore += contribution
                existing.inFTS = true
                table[key] = existing
            } else {
                table[key] = Entry(
                    rrfScore: contribution,
                    text: result.snippet.isEmpty ? result.chapterTitle : result.snippet,
                    bookId: result.bookId,
                    chapter: result.chapterTitle,
                    inFTS: true,
                    inVector: false
                )
            }
        }

        for (rank, result) in vectorResults.enumerated() {
            let key = "vec:\(result.bookId):\(result.startOffset)"
            let contribution = 1.0 / (rrfConstant + Double(rank + 1))
            if var existing = table[key] {
                existing.rrfScore += contribution
                existing.inVector = true
                table[key] = existing
            } else {
                table[key] = Entry(
                    rrfScore: contribution,
                    text: result.chunkText,
                    bookId: result.bookId,
                    chapter: result.chapter,
                    inFTS: false,
                    inVector: true
                )
            }
        }

        let sorted = table.values.sorted { $0.rrfScore > $1.rrfScore }
        return sorted.prefix(limit).map { entry in
            let source: HybridSearchSource
            if entry.inFTS && entry.inVector {
                source = .both
            } else if entry.inFTS {
                source = .fts
            } else {
                source = .vector
            }
            return HybridSearchResult(
                text: entry.text,
                score: entry.rrfScore,
                source: source,
                bookId: entry.bookId,
                chapter: entry.chapter
            )
        }
    }
}
