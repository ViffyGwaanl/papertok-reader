import Foundation
import Testing
@testable import PTFeatures

@Suite("PDFPageTransitionController")
@MainActor
struct PDFPageTransitionTests {
    @Test("Programmatic page change triggers transition flag")
    func programmaticPageChangeTriggersTransitionFlag() async {
        let controller = PDFPageTransitionController(fadeDurationMS: 150)
        #expect(controller.isTransitioning == false)
        controller.triggerTransition()
        #expect(controller.isTransitioning == true)
    }

    @Test("Transition flag resets after the configured delay")
    func transitionFlagResetsAfterDelay() async {
        let controller = PDFPageTransitionController(fadeDurationMS: 40)
        controller.triggerTransition()
        #expect(controller.isTransitioning == true)
        // Wait a little longer than the fade duration.
        try? await Task.sleep(nanoseconds: 120_000_000) // 120ms
        #expect(controller.isTransitioning == false)
    }

    @Test("Rapid re-trigger keeps the flag active and extends the window")
    func rapidRetriggerKeepsFlagActive() async {
        let controller = PDFPageTransitionController(fadeDurationMS: 60)
        controller.triggerTransition()
        try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        controller.triggerTransition()
        // After the original 60ms window elapses, the flag should still be true
        // because the re-trigger reset the timer.
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms (total 70ms)
        #expect(controller.isTransitioning == true)
        try? await Task.sleep(nanoseconds: 60_000_000) // wait past the second window
        #expect(controller.isTransitioning == false)
    }
}
