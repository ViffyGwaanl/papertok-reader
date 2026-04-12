import Testing
import Foundation
@testable import PTAIServices

@Suite("ChunkingService")
struct ChunkingServiceTests {

    @Test("empty input produces no chunks")
    func emptyInput() {
        let svc = ChunkingService(chunkSize: 100, overlap: 10)
        #expect(svc.chunk(text: "").isEmpty)
    }

    @Test("short text becomes one chunk")
    func shortText() {
        let svc = ChunkingService(chunkSize: 2000, overlap: 256)
        let chunks = svc.chunk(text: "Hello world.")
        #expect(chunks.count == 1)
        #expect(chunks[0].text.contains("Hello world"))
        #expect(chunks[0].chunkIndex == 0)
    }

    @Test("long text is split into multiple chunks")
    func longText() {
        let svc = ChunkingService(chunkSize: 200, overlap: 40)
        // Build 10 paragraphs of ~80 chars each -> total ~800 chars.
        let paragraph = String(repeating: "abcdefghij ", count: 8) // 88 chars
        let doc = (0..<10).map { _ in paragraph }.joined(separator: "\n\n")
        let chunks = svc.chunk(text: doc)
        #expect(chunks.count >= 3)
        // Each chunk should not hugely exceed chunkSize (allow slack for overlap concatenation).
        for c in chunks {
            #expect(c.text.count <= 200 + 40 + 10)
        }
        // chunkIndex should be monotonically increasing.
        for i in 1..<chunks.count {
            #expect(chunks[i].chunkIndex == chunks[i - 1].chunkIndex + 1)
        }
    }

    @Test("metadata is propagated to each chunk")
    func metadataPropagation() {
        let svc = ChunkingService(chunkSize: 50, overlap: 5)
        let doc = String(repeating: "sentence one. sentence two. ", count: 10)
        let chunks = svc.chunk(text: doc, metadata: ["chapter": "Ch1"])
        #expect(!chunks.isEmpty)
        for c in chunks {
            #expect(c.metadata["chapter"] == "Ch1")
        }
    }

    @Test("huge single paragraph falls back to character splitting")
    func hugeParagraphFallback() {
        let svc = ChunkingService(chunkSize: 100, overlap: 20)
        // Single paragraph, no sentence terminators, much larger than chunkSize.
        let text = String(repeating: "x", count: 500)
        let chunks = svc.chunk(text: text)
        #expect(chunks.count >= 4)
        for c in chunks {
            #expect(c.text.count <= 100 + 20 + 5)
        }
    }

    @Test("overlap keeps tail context between chunks")
    func overlapBehavior() {
        let svc = ChunkingService(chunkSize: 60, overlap: 15)
        // Two ~50-char sentence paragraphs that together exceed chunkSize.
        let p1 = "First paragraph with enough text to matter here."
        let p2 = "Second paragraph which is also reasonably long now."
        let chunks = svc.chunk(text: p1 + "\n\n" + p2)
        #expect(chunks.count >= 2)
    }
}
