import XCTest
@testable import PTAIServices

final class FulltextTranslationCacheTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pt-cache-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testLookupMissReturnsNil() async {
        let cache = FulltextTranslationCache(directory: directory)
        let v = await cache.lookup(originalText: "hello", source: "en", target: "zh-Hans")
        XCTAssertNil(v)
    }

    func testStoreAndLookupRoundtrip() async {
        let cache = FulltextTranslationCache(directory: directory)
        await cache.store(originalText: "hello", source: "en", target: "zh-Hans", translation: "你好")
        let v = await cache.lookup(originalText: "hello", source: "en", target: "zh-Hans")
        XCTAssertEqual(v, "你好")
    }

    func testDifferentLanguagePairsAreDistinct() async {
        let cache = FulltextTranslationCache(directory: directory)
        await cache.store(originalText: "hello", source: "en", target: "zh-Hans", translation: "你好")
        await cache.store(originalText: "hello", source: "en", target: "ja", translation: "こんにちは")
        let zh = await cache.lookup(originalText: "hello", source: "en", target: "zh-Hans")
        let ja = await cache.lookup(originalText: "hello", source: "en", target: "ja")
        XCTAssertEqual(zh, "你好")
        XCTAssertEqual(ja, "こんにちは")
    }

    func testCorruptedFileIsDeletedOnLookup() async throws {
        let cache = FulltextTranslationCache(directory: directory)
        await cache.store(originalText: "hi", source: "en", target: "zh-Hans", translation: "嗨")
        // Force a fresh actor so memory cache is cold.
        let key = FulltextTranslationCache.key(text: "hi", source: "en", target: "zh-Hans")
        let fileURL = directory.appendingPathComponent("\(key).json")
        try "not-json".write(to: fileURL, atomically: true, encoding: .utf8)

        let fresh = FulltextTranslationCache(directory: directory)
        let v = await fresh.lookup(originalText: "hi", source: "en", target: "zh-Hans")
        XCTAssertNil(v)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testPurgeClearsEverything() async {
        let cache = FulltextTranslationCache(directory: directory)
        await cache.store(originalText: "a", source: "en", target: "zh-Hans", translation: "啊")
        await cache.purge()
        let v = await cache.lookup(originalText: "a", source: "en", target: "zh-Hans")
        XCTAssertNil(v)
    }

    func testPersistenceAcrossActorRestarts() async {
        let a = FulltextTranslationCache(directory: directory)
        await a.store(originalText: "persist", source: "en", target: "zh-Hans", translation: "持久")
        let b = FulltextTranslationCache(directory: directory)
        let v = await b.lookup(originalText: "persist", source: "en", target: "zh-Hans")
        XCTAssertEqual(v, "持久")
    }
}
