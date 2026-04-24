import Foundation
import Testing
@testable import PTFeatures

/// W7.1 — Reader immersion core: chrome visibility + auto-hide timer.
@Suite("ReaderChromeVisibility")
@MainActor
struct ReaderChromeVisibilityTests {
    /// Captures sleep calls so each test can advance the virtual clock
    /// without waiting in real-time. The sleeper resolves after its actor
    /// `continuation` is signalled via `resolveNext()`.
    private final class FakeSleeper: @unchecked Sendable {
        private let lock = NSLock()
        private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
        private(set) var recordedDelays: [Double] = []

        func sleep(seconds: Double) async {
            await withCheckedContinuation { continuation in
                lock.lock()
                recordedDelays.append(seconds)
                pendingContinuations.append(continuation)
                lock.unlock()
            }
        }

        /// Resolves the oldest pending sleep, simulating elapsed time.
        func advance() {
            lock.lock()
            let cont = pendingContinuations.isEmpty ? nil : pendingContinuations.removeFirst()
            lock.unlock()
            cont?.resume()
        }

        var pendingCount: Int {
            lock.lock(); defer { lock.unlock() }
            return pendingContinuations.count
        }
    }

    @Test("Chrome starts visible when reader appears")
    func chromeStartsVisibleOnOpen() async {
        let controller = ReaderChromeVisibilityController(autoHideSeconds: 0)
        controller.onReaderAppear()
        #expect(controller.isChromeVisible == true)
    }

    @Test("toggleChrome flips state both directions")
    func toggleChromeFlipsState() async {
        let controller = ReaderChromeVisibilityController(autoHideSeconds: 0)
        controller.onReaderAppear()
        #expect(controller.isChromeVisible == true)
        controller.toggleChrome()
        #expect(controller.isChromeVisible == false)
        controller.toggleChrome()
        #expect(controller.isChromeVisible == true)
    }

    @Test("Auto-hide timer hides chrome after configured delay")
    func autoHideTimerHidesAfterDelay() async {
        let sleeper = FakeSleeper()
        let controller = ReaderChromeVisibilityController(
            autoHideSeconds: 0.1,
            sleeper: { await sleeper.sleep(seconds: $0) }
        )
        controller.onReaderAppear()
        #expect(controller.isChromeVisible == true)

        // Wait for the controller's hide task to enter the sleep loop.
        for _ in 0..<50 {
            if sleeper.pendingCount > 0 { break }
            await Task.yield()
        }
        #expect(sleeper.recordedDelays.contains(0.1))

        sleeper.advance()
        // Let the continuation propagate back to the MainActor hop.
        for _ in 0..<50 {
            if controller.isChromeVisible == false { break }
            await Task.yield()
        }
        #expect(controller.isChromeVisible == false)
    }

    @Test("Manual toggle cancels pending auto-hide timer")
    func autoHideCancelledOnManualToggle() async {
        let sleeper = FakeSleeper()
        let controller = ReaderChromeVisibilityController(
            autoHideSeconds: 0.1,
            sleeper: { await sleeper.sleep(seconds: $0) }
        )
        controller.onReaderAppear()
        for _ in 0..<50 {
            if sleeper.pendingCount > 0 { break }
            await Task.yield()
        }
        #expect(sleeper.pendingCount == 1)

        // User taps to hide immediately — pending auto-hide should be cancelled
        // so no phantom hide fires after the second tap (which would re-show).
        controller.toggleChrome()
        #expect(controller.isChromeVisible == false)

        // Resolve the (now-orphaned) continuation and verify state stays false
        // (the cancelled task must ignore the wake-up).
        sleeper.advance()
        for _ in 0..<50 { await Task.yield() }
        #expect(controller.isChromeVisible == false)
    }

    @Test("Auto-hide disabled when seconds is zero")
    func autoHideDisabledWhenSecondsZero() async {
        let sleeper = FakeSleeper()
        let controller = ReaderChromeVisibilityController(
            autoHideSeconds: 0,
            sleeper: { await sleeper.sleep(seconds: $0) }
        )
        controller.onReaderAppear()
        for _ in 0..<10 { await Task.yield() }
        #expect(sleeper.pendingCount == 0)
        #expect(controller.isChromeVisible == true)
    }
}
