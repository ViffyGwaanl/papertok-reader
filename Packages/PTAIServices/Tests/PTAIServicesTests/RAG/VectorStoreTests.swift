import Testing
import Foundation
@testable import PTAIServices

@Suite("VectorStore")
struct VectorStoreTests {

    private func makeStore() -> VectorStore {
        // Each test gets its own temp-file database (in-memory SQLite would
        // reset on every new connection because VectorStore opens one per call).
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vstore-\(UUID().uuidString).db")
        return VectorStore(databasePath: tmp.path)
    }

    @Test("stores and retrieves exact vector with score 1.0")
    func storeAndRetrieve() async throws {
        let store = makeStore()
        let chunk = TextChunk(
            text: "hello world",
            startOffset: 0,
            endOffset: 11,
            chunkIndex: 0,
            metadata: ["chapter": "Intro"]
        )
        let vec: [Float] = [1.0, 0.0, 0.0, 0.0]
        try await store.store(chunks: [chunk], embeddings: [vec], bookId: 42)

        let count = try await store.count()
        #expect(count == 1)

        let hits = try await store.search(queryEmbedding: vec, limit: 5)
        #expect(hits.count == 1)
        #expect(hits[0].chunkText == "hello world")
        #expect(hits[0].bookId == 42)
        #expect(hits[0].chapter == "Intro")
        #expect(hits[0].score > 0.99)
    }

    @Test("ranks more similar vectors higher")
    func rankingOrder() async throws {
        let store = makeStore()
        let a = TextChunk(text: "A", startOffset: 0, endOffset: 1, chunkIndex: 0)
        let b = TextChunk(text: "B", startOffset: 2, endOffset: 3, chunkIndex: 1)
        let c = TextChunk(text: "C", startOffset: 4, endOffset: 5, chunkIndex: 2)

        let vA: [Float] = [1.0, 0.0, 0.0]
        let vB: [Float] = [0.9, 0.1, 0.0]
        let vC: [Float] = [0.0, 1.0, 0.0]

        try await store.store(chunks: [a, b, c], embeddings: [vA, vB, vC], bookId: 1)

        let hits = try await store.search(queryEmbedding: [1.0, 0.0, 0.0], limit: 3)
        #expect(hits.count == 3)
        #expect(hits[0].chunkText == "A")
        #expect(hits[1].chunkText == "B")
        #expect(hits[2].chunkText == "C")
        #expect(hits[0].score >= hits[1].score)
        #expect(hits[1].score >= hits[2].score)
    }

    @Test("respects bookId filter")
    func bookIdFilter() async throws {
        let store = makeStore()
        let c1 = TextChunk(text: "book1", startOffset: 0, endOffset: 5, chunkIndex: 0)
        let c2 = TextChunk(text: "book2", startOffset: 0, endOffset: 5, chunkIndex: 0)
        try await store.store(chunks: [c1], embeddings: [[1, 0, 0]], bookId: 1)
        try await store.store(chunks: [c2], embeddings: [[1, 0, 0]], bookId: 2)

        let onlyBook2 = try await store.search(queryEmbedding: [1, 0, 0], limit: 10, bookId: 2)
        #expect(onlyBook2.count == 1)
        #expect(onlyBook2[0].chunkText == "book2")

        let allBooks = try await store.search(queryEmbedding: [1, 0, 0], limit: 10)
        #expect(allBooks.count == 2)
    }

    @Test("removeBook drops only targeted rows")
    func removeBook() async throws {
        let store = makeStore()
        let c1 = TextChunk(text: "x", startOffset: 0, endOffset: 1, chunkIndex: 0)
        let c2 = TextChunk(text: "y", startOffset: 0, endOffset: 1, chunkIndex: 0)
        try await store.store(chunks: [c1], embeddings: [[1, 0]], bookId: 10)
        try await store.store(chunks: [c2], embeddings: [[0, 1]], bookId: 20)

        try await store.removeBook(bookId: 10)
        #expect(try await store.count(bookId: 10) == 0)
        #expect(try await store.count(bookId: 20) == 1)
    }

    @Test("clear removes everything")
    func clearAll() async throws {
        let store = makeStore()
        let c = TextChunk(text: "z", startOffset: 0, endOffset: 1, chunkIndex: 0)
        try await store.store(chunks: [c], embeddings: [[1, 0]], bookId: 7)
        try await store.clear()
        #expect(try await store.count() == 0)
    }

    @Test("float <-> Data round-trip preserves values")
    func floatDataRoundTrip() {
        let input: [Float] = [0.0, -1.5, 3.14, 42.0, .leastNormalMagnitude]
        let data = VectorStore.dataFromFloats(input)
        #expect(data.count == input.count * MemoryLayout<Float>.size)
        let output = VectorStore.floatsFromData(data)
        #expect(output == input)
    }
}
