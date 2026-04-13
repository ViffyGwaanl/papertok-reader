import SwiftUI
import PTUI

#if canImport(UIKit)
import UIKit
#endif

/// Compact slider for adjusting screen brightness from inside the reader.
///
/// On iOS this writes directly to `UIScreen.main.brightness`. On macOS the
/// view becomes a no-op disabled slider so it can still be embedded in
/// shared settings UI.
public struct ScreenBrightnessSlider: View {
    @State private var brightness: Double

    public init() {
        #if canImport(UIKit)
        _brightness = State(initialValue: Double(UIScreen.main.brightness))
        #else
        _brightness = State(initialValue: 1.0)
        #endif
    }

    public var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "sun.min")
                .foregroundStyle(Morandi.secondaryText)
            Slider(value: $brightness, in: 0...1)
                .tint(Morandi.accent)
                .onChange(of: brightness) { _, newValue in
                    apply(newValue)
                }
            Image(systemName: "sun.max")
                .foregroundStyle(Morandi.secondaryText)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(
            Capsule().fill(Morandi.cardBackground)
        )
#if !canImport(UIKit)
        .disabled(true)
#endif
        .onAppear {
            #if canImport(UIKit)
            brightness = Double(UIScreen.main.brightness)
            #endif
        }
    }

    private func apply(_ value: Double) {
        #if canImport(UIKit)
        UIScreen.main.brightness = CGFloat(value)
        #endif
    }
}

/// Helper for toggling iOS idle timer (wake lock) so the screen stays on.
public enum WakeLockController {
    public static func setKeepScreenOn(_ keepOn: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = keepOn
        #endif
    }
}
