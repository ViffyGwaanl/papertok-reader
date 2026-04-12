import Foundation
import Testing
@testable import PaperTokReader

@Suite("PendingAIRequestStore")
struct PendingAIRequestStoreTests {
    @Test("queue entries move from pending to completed with a returned answer")
    func requestLifecycle() throws {
        let suiteName = "PendingAIRequestStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PendingAIRequestStore(defaults: defaults)
        let request = store.enqueue(
            prompt: "Summarize this image",
            images: [
                PendingAIRequestImage(
                    filename: "share.jpg",
                    mediaType: "image/jpeg",
                    data: Data([0xFF, 0xD8, 0xFF])
                )
            ],
            source: .appIntent
        )

        let queued = store.requests
        #expect(queued.count == 1)
        #expect(queued[0].status == .pending)

        store.markStarted(id: request.id)
        #expect(store.requests.first?.status == .running)

        store.markCompleted(id: request.id, responseText: "A concise answer")
        let completed = try #require(store.requests.first)
        #expect(completed.status == .completed)
        #expect(completed.responseText == "A concise answer")
        #expect(completed.prompt == "Summarize this image")
    }
}
