import SwiftUI
import PTUI

/// Three-dot bouncing typing indicator shown while waiting for the first stream token.
struct TypingIndicatorView: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            assistantAvatar
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Morandi.secondaryText)
                        .frame(width: 7, height: 7)
                        .opacity(phase == i ? 1.0 : 0.35)
                        .scaleEffect(phase == i ? 1.15 : 0.9)
                        .animation(.easeInOut(duration: 0.25), value: phase)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Morandi.cardBackground)
            )
            Spacer(minLength: 48)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }

    private var assistantAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Morandi.accent, Morandi.lavender],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
