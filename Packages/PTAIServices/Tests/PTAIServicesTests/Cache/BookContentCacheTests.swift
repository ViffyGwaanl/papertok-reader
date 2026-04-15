import Testing
import Foundation
@testable import PTAIServices

@Suite("BookContentCache")
struct BookContentCacheTests {
    @Test("get returns nil on miss")
    func getReturnsNilOnMiss() async {
        let cache = BookContentCache()
        let key = BookContentCache.Key(bookId: "b1", scope: .epubWholeBook)
        let value = await cache.get(key)
        #expect(value == nil)
    }

    @Test("set and get round trip")
    func setAndGetRoundTrip() async {
        let cache = BookContentCache()
        let key = BookContentCache.Key(bookId: "b1", scope: .epubChapter(href: "c1.xhtml"))
        await cache.set(key, value: "chapter text")
        let value = await cache.get(key)
        #expect(value == "chapter text")
        let count = await cache.count()
        #expect(count == 1)
    }

    @Test("LRU eviction removes oldest on overflow")
    func lruEvictionRemovesOldestOnOverflow() async {
        let cache = BookContentCache(maxEntries: 2)
        let k1 = BookContentCache.Key(bookId: "b", scope: .pdfPage(index: 1))
        let k2 = BookContentCache.Key(bookId: "b", scope: .pdfPage(index: 2))
        let k3 = BookContentCache.Key(bookId: "b", scope: .pdfPage(index: 3))
        await cache.set(k1, value: "one")
        await cache.set(k2, value: "two")
        await cache.set(k3, value: "three")
        let v1 = await cache.get(k1)
        let v2 = await cache.get(k2)
        let v3 = await cache.get(k3)
        #expect(v1 == nil)
        #expect(v2 == "two")
        #expect(v3 == "three")
        let count = await cache.count()
        #expect(count == 2)
    }

    @Test("get moves entry to most recently used")
    func getMovesEntryToMostRecentlyUsed() async {
        let cache = BookContentCache(maxEntries: 2)
        let k1 = BookContentCache.Key(bookId: "b", scope: .pdfPage(index: 1))
        let k2 = BookContentCache.Key(bookId: "b", scope: .pdfPage(index: 2))
        let k3 = BookContentCache.Key(bookId: "b", scope: .pdfPage(index: 3))
        await cache.set(k1, value: "one")
        await cache.set(k2, value: "two")
        // Touch k1 so k2 becomes the oldest
        _ = await cache.get(k1)
        await cache.set(k3, value: "three")
        let v1 = await cache.get(k1)
        let v2 = await cache.get(k2)
        let v3 = await cache.get(k3)
        #expect(v1 == "one")
        #expect(v2 == nil)
        #expect(v3 == "three")
    }

    @Test("clear removes all entries")
    func clearRemovesAllEntries() async {
        let cache = BookContentCache()
        let k1 = BookContentCache.Key(bookId: "b", scope: .epubWholeBook)
        let k2 = BookContentCache.Key(bookId: "b", scope: .pdfWholeBook)
        await cache.set(k1, value: "a")
        await cache.set(k2, value: "b")
        await cache.clear()
        let count = await cache.count()
        #expect(count == 0)
        let v1 = await cache.get(k1)
        #expect(v1 == nil)
    }

    @Test("different bookIds are distinct keys")
    func differentBookIdsAreDistinctKeys() async {
        let cache = BookContentCache()
        let k1 = BookContentCache.Key(bookId: "b1", scope: .epubWholeBook)
        let k2 = BookContentCache.Key(bookId: "b2", scope: .epubWholeBook)
        await cache.set(k1, value: "first")
        await cache.set(k2, value: "second")
        let v1 = await cache.get(k1)
        let v2 = await cache.get(k2)
        #expect(v1 == "first")
        #expect(v2 == "second")
    }

    @Test("different scopes for same book are distinct keys")
    func differentScopesForSameBookAreDistinctKeys() async {
        let cache = BookContentCache()
        let k1 = BookContentCache.Key(bookId: "b", scope: .epubChapter(href: "a"))
        let k2 = BookContentCache.Key(bookId: "b", scope: .epubChapter(href: "b"))
        let k3 = BookContentCache.Key(bookId: "b", scope: .epubWholeBook)
        let k4 = BookContentCache.Key(bookId: "b", scope: .pdfChapter(startPage: 0, endPage: 5))
        let k5 = BookContentCache.Key(bookId: "b", scope: .pdfChapter(startPage: 6, endPage: 10))
        await cache.set(k1, value: "1")
        await cache.set(k2, value: "2")
        await cache.set(k3, value: "3")
        await cache.set(k4, value: "4")
        await cache.set(k5, value: "5")
        let v1 = await cache.get(k1)
        let v2 = await cache.get(k2)
        let v3 = await cache.get(k3)
        let v4 = await cache.get(k4)
        let v5 = await cache.get(k5)
        #expect(v1 == "1")
        #expect(v2 == "2")
        #expect(v3 == "3")
        #expect(v4 == "4")
        #expect(v5 == "5")
    }
}
