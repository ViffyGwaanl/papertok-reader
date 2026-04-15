import XCTest
@testable import PTAIServices

private actor SpyTranslator: Translator {
    private(set) var callCount: Int = 0
    private(set) var maxInFlight: Int = 0
    private var currentInFlight: Int = 0
    private let delay: UInt64
    private let output: (String) -> String

    init(delayNanos: UInt64 = 0, output: @escaping (String) -> String = { "[t]\($0)" }) {
        self.delay = delayNanos
        self.output = output
    }

    func calls() -> Int { callCount }
    func peakInFlight() -> Int { maxInFlight }

    nonisolated func translate(_ text: String, from source: String, to target: String) async throws -> String {
        try await enter()
        defer { Task { await self.leave() } }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        return output(text)
    }

    private func enter() async throws {
        callCount += 1
        currentInFlight += 1
        if currentInFlight > maxInFlight { maxInFlight = currentInFlight }
    }

    private func leave() {
        currentInFlight -= 1
    }
}

private actor GatedTranslator: Translator {
    private var continuations: [CheckedContinuation<String, Error>] = []
    private(set) var pendingCount: Int = 0

    nonisolated func translate(_ text: String, from source: String, to target: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            Task { await self.enqueue(cont: cont, text: text) }
        }
    }

    private func enqueue(cont: CheckedContinuation<String, Error>, text: String) {
        continuations.append(cont)
        pendingCount += 1
    }

    func releaseAll(transform: (Int) -> String) {
        let conts = continuations
        continuations.removeAll()
        for (i, c) in conts.enumerated() {
            c.resume(returning: transform(i))
        }
        pendingCount = 0
    }

    func pending() -> Int { pendingCount }
}

@MainActor
final class FulltextTranslationRuntimeTests: XCTestCase {
    private func makeCache() -> FulltextTranslationCache {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pt-runtime-\(UUID().uuidString)", isDirectory: true)
        return FulltextTranslationCache(directory: dir)
    }

    private func waitUntil(timeout: TimeInterval = 2.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testQueuesAndTransitionsToReady() async {
        let translator = SpyTranslator()
        let runtime = FulltextTranslationRuntime(translator: translator, cache: makeCache())
        await runtime.setParagraphs([("1", "hello"), ("2", "world")])
        await waitUntil { runtime.paragraphs.allSatisfy { $0.status == .ready } }
        XCTAssertEqual(runtime.paragraphs.count, 2)
        XCTAssertEqual(runtime.paragraphs[0].translatedText, "[t]hello")
        XCTAssertEqual(runtime.paragraphs[1].translatedText, "[t]world")
        let calls = await translator.calls()
        XCTAssertEqual(calls, 2)
    }

    func testCacheHitAvoidsTranslatorCall() async {
        let translator = SpyTranslator()
        let cache = makeCache()
        let r1 = FulltextTranslationRuntime(translator: translator, cache: cache)
        await r1.setParagraphs([("1", "hello")])
        await waitUntil { r1.paragraphs.first?.status == .ready }
        let initialCalls = await translator.calls()

        let r2 = FulltextTranslationRuntime(translator: translator, cache: cache)
        await r2.setParagraphs([("1", "hello")])
        await waitUntil { r2.paragraphs.first?.status == .ready }
        let finalCalls = await translator.calls()
        XCTAssertEqual(initialCalls, finalCalls)
        XCTAssertEqual(r2.paragraphs.first?.translatedText, "[t]hello")
    }

    func testIdleCacheHitSkipsTranslatingState() async {
        let translator = SpyTranslator()
        let cache = makeCache()
        await cache.store(originalText: "hello", source: "auto", target: "zh-Hans", translation: "你好")
        let runtime = FulltextTranslationRuntime(translator: translator, cache: cache)
        await runtime.setParagraphs([("1", "hello")])
        XCTAssertEqual(runtime.paragraphs.first?.status, .ready)
        XCTAssertEqual(runtime.paragraphs.first?.translatedText, "你好")
        let calls = await translator.calls()
        XCTAssertEqual(calls, 0)
    }

    func testEvictionCancelsRemovedParagraphs() async {
        let translator = SpyTranslator()
        let runtime = FulltextTranslationRuntime(translator: translator, cache: makeCache())
        await runtime.setParagraphs([("1", "a"), ("2", "b"), ("3", "c")])
        await runtime.setParagraphs([("2", "b")])
        await waitUntil { runtime.paragraphs.count == 1 && runtime.paragraphs.first?.status == .ready }
        XCTAssertEqual(runtime.paragraphs.map(\.id), ["2"])
    }

    func testSetEnabledFalseCancelsAndClears() async {
        let gated = GatedTranslator()
        let runtime = FulltextTranslationRuntime(translator: gated, cache: makeCache())
        await runtime.setEnabled(true)
        await runtime.setParagraphs([("1", "a"), ("2", "b")])
        await runtime.setEnabled(false)
        XCTAssertTrue(runtime.paragraphs.isEmpty)
        XCTAssertFalse(runtime.isEnabled)
        XCTAssertEqual(runtime.inFlightCount, 0)
    }

    func testBoundedConcurrency() async {
        let translator = SpyTranslator(delayNanos: 30_000_000)
        let runtime = FulltextTranslationRuntime(translator: translator, cache: makeCache(), maxConcurrency: 4)
        let originals: [(String, String)] = (0..<10).map { ("p\($0)", "text-\($0)") }
        await runtime.setParagraphs(originals)
        await waitUntil(timeout: 5.0) { runtime.paragraphs.allSatisfy { $0.status == .ready } }
        let peak = await translator.peakInFlight()
        XCTAssertLessThanOrEqual(peak, 4)
        XCTAssertGreaterThan(peak, 1)
    }

    func testStaleResultDoesNotMutateEvictedParagraph() async {
        let gated = GatedTranslator()
        let runtime = FulltextTranslationRuntime(translator: gated, cache: makeCache())
        await runtime.setParagraphs([("1", "slow")])
        await waitUntil { runtime.paragraphs.first?.status == .translating }
        // Evict before the slow result lands.
        await runtime.setParagraphs([])
        XCTAssertTrue(runtime.paragraphs.isEmpty)
        // Now release the slow continuation — must not crash or mutate state.
        await gated.releaseAll { _ in "late" }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(runtime.paragraphs.isEmpty)
    }
}
