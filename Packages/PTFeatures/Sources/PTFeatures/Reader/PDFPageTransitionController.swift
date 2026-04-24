import Foundation
import Observation

/// Small observable helper that coordinates a subtle fade overlay whenever
/// the PDF reader performs a programmatic page jump (keyboard shortcut,
/// toolbar button, TOC tap). Native swipe/scroll gestures should *not*
/// route through this — their animation already feels intentional.
///
/// The overlay view observes `isTransitioning`: when true, a translucent
/// colour layer is faded in; the flag auto-resets after `fadeDurationMS`.
/// Re-triggering restarts the window (so rapid jumps stay covered until
/// the final jump settles).
@MainActor @Observable
public final class PDFPageTransitionController {
    public private(set) var isTransitioning: Bool = false

    private let fadeDurationMS: Int
    private var currentTask: Task<Void, Never>?

    public init(fadeDurationMS: Int = 150) {
        self.fadeDurationMS = fadeDurationMS
    }

    /// Flip the transition flag on and schedule auto-reset after the
    /// configured fade window. Calling again while the flag is on
    /// restarts the window (cancels the previous reset task).
    public func triggerTransition() {
        currentTask?.cancel()
        isTransitioning = true
        let delay = fadeDurationMS
        currentTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            if Task.isCancelled { return }
            self?.isTransitioning = false
        }
    }
}
