import Foundation
import SwiftUI

#if os(iOS)
import AVFoundation
import MediaPlayer
import UIKit

/// Observes hardware volume button presses and forwards them to the
/// reader as page-turn callbacks.
///
/// Implementation notes:
/// - We KVO `AVAudioSession.outputVolume`, which is the standard
///   technique to detect physical volume button presses on iOS.
/// - To keep the system volume HUD hidden, an off-screen `MPVolumeView`
///   is added to the key window so iOS routes the slider event without
///   showing the on-screen overlay.
/// - We snap the volume back to the previous value after each press to
///   avoid unbounded drift in either direction.
@MainActor
public final class VolumeKeyHandler: ObservableObject {
    public var onVolumeUp: (() -> Void)?
    public var onVolumeDown: (() -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private var observer: NSKeyValueObservation?
    private var hiddenVolumeView: MPVolumeView?
    private var lastObservedVolume: Float = 0.5
    private var isStarted = false

    public init() {}

    deinit {
        observer?.invalidate()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal: page-turn keys simply won't fire.
        }

        lastObservedVolume = session.outputVolume
        installHiddenVolumeView()

        observer = session.observe(\.outputVolume, options: [.new, .old]) { [weak self] _, change in
            Task { @MainActor [weak self] in
                self?.handleVolumeChange(new: change.newValue, old: change.oldValue)
            }
        }
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        observer?.invalidate()
        observer = nil
        hiddenVolumeView?.removeFromSuperview()
        hiddenVolumeView = nil
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func handleVolumeChange(new: Float?, old: Float?) {
        guard let new else { return }
        let previous = old ?? lastObservedVolume
        let delta = new - previous

        if abs(delta) < 0.0001 {
            return
        }

        if delta > 0 {
            onVolumeUp?()
        } else {
            onVolumeDown?()
        }

        // Reset back to the baseline so we always have headroom to detect
        // the next press in either direction without showing the HUD.
        lastObservedVolume = previous
        restoreVolume(to: previous)
    }

    private func installHiddenVolumeView() {
        guard hiddenVolumeView == nil else { return }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first else {
            return
        }
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        view.alpha = 0.0001
        view.isUserInteractionEnabled = false
        window.addSubview(view)
        hiddenVolumeView = view
    }

    private func restoreVolume(to value: Float) {
        guard let slider = hiddenVolumeView?.subviews.compactMap({ $0 as? UISlider }).first else {
            return
        }
        // Apple docs require dispatching to the next runloop turn so the
        // KVO callback finishes before we mutate volume again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            slider.value = value
        }
    }
}
#else
@MainActor
public final class VolumeKeyHandler: ObservableObject {
    public var onVolumeUp: (() -> Void)?
    public var onVolumeDown: (() -> Void)?
    public init() {}
    public func start() {}
    public func stop() {}
}
#endif
