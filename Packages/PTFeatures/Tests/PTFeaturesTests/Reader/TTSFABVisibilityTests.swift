import Foundation
import Testing
@testable import PTFeatures
import PTReader

#if canImport(AVFoundation)

/// W7.5 — Bug #2: the TTS floating-action-button used to be visible the
/// entire time a book was open. Users complained:
///   "朗读的功能 不要一直显示着 在播放的时候才显示".
///
/// The new visibility predicate combines "is a book loaded" with
/// `TTSState.isActiveOrPaused`: the FAB only appears while playback is
/// running or paused. The toolbar gains a "Start Reading" button that
/// kicks playback off (which then makes the FAB visible).
@Suite("TTS FAB visibility")
@MainActor
struct TTSFABVisibilityTests {
    @Test("fabHiddenWhenStateIdle — fresh service in .stopped hides the FAB")
    func fabHiddenWhenStateIdle() {
        let publicationLoaded = true
        let service = TTSService()
        #expect(service.state == .stopped)
        #expect(ReaderTTSFABVisibility.shouldShow(
            publicationLoaded: publicationLoaded,
            state: service.state
        ) == false)
    }

    @Test("fabVisibleWhenStatePlaying — .speaking with a publication shows the FAB")
    func fabVisibleWhenStatePlaying() {
        #expect(ReaderTTSFABVisibility.shouldShow(
            publicationLoaded: true,
            state: .speaking
        ) == true)
    }

    @Test("fabVisibleWhenStatePaused — .paused state still shows the FAB so user can resume")
    func fabVisibleWhenStatePaused() {
        #expect(ReaderTTSFABVisibility.shouldShow(
            publicationLoaded: true,
            state: .paused
        ) == true)
    }

    @Test("fabHiddenWithoutPublication — even active state stays hidden if no book is loaded")
    func fabHiddenWithoutPublication() {
        // Defensive: callers should never invoke TTS without a book, but the
        // FAB visibility is still gated on "publication != nil".
        #expect(ReaderTTSFABVisibility.shouldShow(
            publicationLoaded: false,
            state: .speaking
        ) == false)
        #expect(ReaderTTSFABVisibility.shouldShow(
            publicationLoaded: false,
            state: .paused
        ) == false)
        #expect(ReaderTTSFABVisibility.shouldShow(
            publicationLoaded: false,
            state: .stopped
        ) == false)
    }
}
#endif
