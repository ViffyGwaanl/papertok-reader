import Testing
import os
@testable import PTCore

@Suite("PerformanceSignposts")
struct PerformanceSignpostsTests {
    @Test("begin and end pairs complete without crashing")
    func signpostBeginEndDoesNotCrash() {
        let bookId = PerformanceSignposts.beginBookOpen()
        PerformanceSignposts.endBookOpen(bookId)

        let chatId = PerformanceSignposts.beginChatSend()
        PerformanceSignposts.endChatSend(chatId)

        let chapterId = PerformanceSignposts.beginChapterEnum()
        PerformanceSignposts.endChapterEnum(chapterId)
    }

    @Test("successive begin calls return unique signpost IDs")
    func signpostIDsAreUnique() {
        let id1 = PerformanceSignposts.beginBookOpen()
        let id2 = PerformanceSignposts.beginBookOpen()
        #expect(id1 != id2)

        // Clean up
        PerformanceSignposts.endBookOpen(id1)
        PerformanceSignposts.endBookOpen(id2)
    }
}
