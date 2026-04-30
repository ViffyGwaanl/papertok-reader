import Foundation
import PTReader

#if canImport(AVFoundation)

/// W7.5 — Bug #2: predicate driving the reader's TTS floating-action-button
/// visibility. Previously the FAB was overlaid whenever a publication was
/// open, which felt noisy ("朗读的功能 不要一直显示着 在播放的时候才显示").
///
/// The button is now gated on both:
///   - whether a publication / PDF document is actually loaded, and
///   - the underlying `TTSService.state`: only `.speaking` or `.paused`
///     keep the FAB on screen so the user can pause / resume / stop.
///
/// The "Start Reading" toolbar button is the new entry point that flips
/// playback on; once playback stops the FAB recedes again.
public enum ReaderTTSFABVisibility {
    public static func shouldShow(publicationLoaded: Bool, state: TTSState) -> Bool {
        publicationLoaded && state.isActiveOrPaused
    }
}
#endif
