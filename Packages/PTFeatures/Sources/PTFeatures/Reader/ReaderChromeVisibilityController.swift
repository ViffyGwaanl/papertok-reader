import Foundation
import Observation
import SwiftUI

/// W7.1 — Reader immersion core.
///
/// Owns the visibility state of the reader's chrome (toolbar + status bar
/// + `ReadingInfoOverlay`). Chrome is visible when the user first opens a
/// book, fades out automatically after `autoHideSeconds`, and toggles on
/// each manual tap into the centre third of the reader. This behaviour
/// matches Apple Books / Kindle / Moon+ conventions.
///
/// The controller is intentionally independent of SwiftUI so its logic is
/// fully testable. Views bind to `isChromeVisible` via `@Bindable`.
@MainActor
@Observable
public final class ReaderChromeVisibilityController {
    /// Current visibility. Views should mirror toolbar / status bar / info
    /// overlay visibility against this flag.
    public private(set) var isChromeVisible: Bool = true

    /// Seconds to wait after chrome becomes visible before auto-hiding.
    /// `0` disables the auto-hide timer entirely.
    public var autoHideSeconds: Double

    /// Injection seam for the sleep routine so tests can run the timer
    /// without actually waiting 3 real seconds.
    public typealias Sleeper = @Sendable (Double) async -> Void

    private let sleeper: Sleeper
    private var hideTask: Task<Void, Never>?

    public init(
        autoHideSeconds: Double = 3.0,
        sleeper: @escaping Sleeper = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.autoHideSeconds = autoHideSeconds
        self.sleeper = sleeper
    }

    /// Called when the reader scene first appears. Chrome starts visible
    /// and immediately schedules an auto-hide (if enabled).
    public func onReaderAppear() {
        isChromeVisible = true
        scheduleAutoHideIfNeeded()
    }

    /// Called when the reader scene disappears so the pending hide task
    /// does not fire against a detached view.
    public func onReaderDisappear() {
        cancelAutoHide()
    }

    /// Explicit toggle triggered by center-third taps. Shows chrome if
    /// hidden (and schedules auto-hide); hides immediately if visible.
    public func toggleChrome() {
        cancelAutoHide()
        isChromeVisible.toggle()
        if isChromeVisible {
            scheduleAutoHideIfNeeded()
        }
    }

    /// Force chrome visible without toggling (e.g. toolbar button pressed).
    public func showChrome() {
        cancelAutoHide()
        isChromeVisible = true
        scheduleAutoHideIfNeeded()
    }

    /// Force chrome hidden without toggling.
    public func hideChrome() {
        cancelAutoHide()
        isChromeVisible = false
    }

    private func scheduleAutoHideIfNeeded() {
        guard autoHideSeconds > 0 else { return }
        let delay = autoHideSeconds
        let sleeper = sleeper
        hideTask = Task { [weak self] in
            await sleeper(delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if self.isChromeVisible {
                    self.isChromeVisible = false
                }
            }
        }
    }

    private func cancelAutoHide() {
        hideTask?.cancel()
        hideTask = nil
    }
}

/// Routes a horizontal tap location into one of three reader zones.
///
/// Dividing the reader surface into thirds mirrors the standard reading
/// convention: left third = back page, right third = forward page, middle
/// third = toggle chrome.
public enum ReaderTapZone: Equatable, Sendable {
    case previousPage
    case toggleChrome
    case nextPage

    /// Resolves a zone from a `0...1` horizontal fraction. The split is
    /// symmetric around the centre third (`1/3 ... 2/3`).
    public static func zone(for horizontalFraction: Double) -> ReaderTapZone {
        let clamped = max(0, min(1, horizontalFraction))
        if clamped < 1.0 / 3.0 {
            return .previousPage
        }
        if clamped > 2.0 / 3.0 {
            return .nextPage
        }
        return .toggleChrome
    }

    /// Convenience wrapper for routing taps from a `GeometryReader`.
    public static func zone(forX x: Double, width: Double) -> ReaderTapZone {
        guard width > 0 else { return .toggleChrome }
        return zone(for: x / width)
    }
}
