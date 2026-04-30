import Testing
import Foundation
@testable import PTReader

#if canImport(AVFoundation)

/// W7.5 — `TTSState.isActiveOrPaused` drives the floating-action-button
/// visibility. The reader-level FAB should only appear while playback is
/// running or paused; it must hide when TTS is fully stopped/idle so the
/// reader chrome stays clean (user feedback: "朗读的功能 不要一直显示着 在播放的时候才显示").
@Suite("TTSState extensions")
struct TTSStateExtensionsTests {
    @Test("idleStateIsNotActive — .stopped maps to false")
    func idleStateIsNotActive() {
        #expect(TTSState.stopped.isActiveOrPaused == false)
    }

    @Test("playingStateIsActive — .speaking maps to true")
    func playingStateIsActive() {
        #expect(TTSState.speaking.isActiveOrPaused == true)
    }

    @Test("pausedStateIsActive — .paused maps to true (FAB stays visible while user is paused)")
    func pausedStateIsActive() {
        #expect(TTSState.paused.isActiveOrPaused == true)
    }

    @Test("stoppedStateIsNotActive — alias for idle")
    func stoppedStateIsNotActive() {
        // The TTSState enum currently has only one terminal/idle case (`stopped`).
        // This test guards against accidental renames or status-promotion regressions.
        let terminal: TTSState = .stopped
        #expect(terminal.isActiveOrPaused == false)
    }
}
#endif
