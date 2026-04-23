import XCTest
@testable import PTAIServices

/// Covers the W6.5 "Retry failed" UX: failed paragraphs must re-enter the
/// worker queue without disturbing paragraphs that are already ready, queued,
/// or in flight. Also exercises the mutable concurrency control.
@MainActor
final class FulltextTranslationRuntimeRetryTests: XCTestCase {

    private final class FailingTranslator: Translator, @unchecked Sendable {
        private var failOnce: Set<String>
        let lock = NSLock()
        init(failOnce: Set<String>) { self.failOnce = failOnce }

        func translate(_ text: String, from source: String, to target: String) async throws -> String {
            lock.lock()
            let shouldFail = failOnce.remove(text) != nil
            lock.unlock()
            if shouldFail {
                throw TestTranslationError.failed
            }
            return "[t]\(text)"
        }
    }

    private enum TestTranslationError: Error { case failed }

    private func makeCache() -> FulltextTranslationCache {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pt-retry-\(UUID().uuidString)", isDirectory: true)
        return FulltextTranslationCache(directory: dir)
    }

    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: @MainActor @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: — tests

    func testRetryFailedParagraphsRequeuesOnlyFailed() async {
        let translator = FailingTranslator(failOnce: ["b", "c"])
        let runtime = FulltextTranslationRuntime(translator: translator, cache: makeCache())
        await runtime.setParagraphs([("1", "a"), ("2", "b"), ("3", "c")])
        await waitUntil { runtime.paragraphs.allSatisfy { $0.status != .queued && $0.status != .translating } }

        XCTAssertEqual(runtime.paragraphs[0].status, .ready)
        XCTAssertTrue({ if case .failed = runtime.paragraphs[1].status { return true } else { return false } }())
        XCTAssertTrue({ if case .failed = runtime.paragraphs[2].status { return true } else { return false } }())

        let requeued = runtime.retryFailedParagraphs()
        XCTAssertEqual(requeued, 2)

        await waitUntil { runtime.paragraphs.allSatisfy { $0.status == .ready } }
        XCTAssertEqual(runtime.paragraphs[0].translatedText, "[t]a")
        XCTAssertEqual(runtime.paragraphs[1].translatedText, "[t]b")
        XCTAssertEqual(runtime.paragraphs[2].translatedText, "[t]c")
    }

    func testRetryDoesNotAffectReadyOrQueuedParagraphs() async {
        let translator = FailingTranslator(failOnce: ["b"])
        let runtime = FulltextTranslationRuntime(translator: translator, cache: makeCache())
        await runtime.setParagraphs([("1", "a"), ("2", "b")])
        await waitUntil {
            runtime.paragraphs.count == 2 &&
            runtime.paragraphs[0].status == .ready &&
            { if case .failed = runtime.paragraphs[1].status { return true } else { return false } }()
        }

        let readyTextBefore = runtime.paragraphs[0].translatedText
        XCTAssertNotNil(readyTextBefore)

        _ = runtime.retryFailedParagraphs()
        // The ready paragraph must remain ready and keep its translation.
        XCTAssertEqual(runtime.paragraphs[0].status, .ready)
        XCTAssertEqual(runtime.paragraphs[0].translatedText, readyTextBefore)

        await waitUntil { runtime.paragraphs[1].status == .ready }
        XCTAssertEqual(runtime.paragraphs[0].translatedText, readyTextBefore)
    }

    func testRetrySetsStatusBackToQueued() async {
        let translator = FailingTranslator(failOnce: ["only"])
        let runtime = FulltextTranslationRuntime(translator: translator, cache: makeCache())
        await runtime.setParagraphs([("1", "only")])
        await waitUntil {
            if case .failed = runtime.paragraphs.first?.status { return true } else { return false }
        }

        // Retry, then snapshot immediately — the paragraph transitions from
        // failed → queued → translating → ready. We only require that the
        // failed marker has been cleared.
        _ = runtime.retryFailedParagraphs()
        let afterRetryStatus = runtime.paragraphs.first?.status
        switch afterRetryStatus {
        case .queued, .translating, .ready:
            break // acceptable — retry has re-entered the worker
        default:
            XCTFail("Expected retry to move paragraph out of .failed, got \(String(describing: afterRetryStatus))")
        }

        await waitUntil { runtime.paragraphs.first?.status == .ready }
        XCTAssertEqual(runtime.paragraphs.first?.translatedText, "[t]only")
    }

    func testRetryWithNoFailuresIsNoop() async {
        let translator = FailingTranslator(failOnce: [])
        let runtime = FulltextTranslationRuntime(translator: translator, cache: makeCache())
        await runtime.setParagraphs([("1", "a"), ("2", "b")])
        await waitUntil { runtime.paragraphs.allSatisfy { $0.status == .ready } }

        let requeued = runtime.retryFailedParagraphs()
        XCTAssertEqual(requeued, 0)
        XCTAssertTrue(runtime.paragraphs.allSatisfy { $0.status == .ready })
    }

    func testSetMaxConcurrencyClampsToSupportedRange() {
        let translator = FailingTranslator(failOnce: [])
        let runtime = FulltextTranslationRuntime(translator: translator, cache: makeCache(), maxConcurrency: 4)

        runtime.setMaxConcurrency(0)
        XCTAssertEqual(runtime.maxConcurrency, 1) // clamp low

        runtime.setMaxConcurrency(99)
        XCTAssertEqual(runtime.maxConcurrency, 8) // clamp high

        runtime.setMaxConcurrency(3)
        XCTAssertEqual(runtime.maxConcurrency, 3)
    }

    func testFailedAndReadyCountersReflectParagraphStates() async {
        let translator = FailingTranslator(failOnce: ["b"])
        let runtime = FulltextTranslationRuntime(translator: translator, cache: makeCache())
        await runtime.setParagraphs([("1", "a"), ("2", "b")])
        await waitUntil {
            runtime.paragraphs.count == 2 &&
            runtime.paragraphs[0].status == .ready &&
            { if case .failed = runtime.paragraphs[1].status { return true } else { return false } }()
        }

        XCTAssertEqual(runtime.readyCount, 1)
        XCTAssertEqual(runtime.failedCount, 1)
        XCTAssertEqual(runtime.totalCount, 2)
        XCTAssertTrue(runtime.hasFailures)
    }
}
