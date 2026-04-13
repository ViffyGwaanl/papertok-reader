import SwiftUI
import PTUI
#if os(iOS)
import UIKit
#endif

/// Chat input bar redesigned to match Flutter main's polished design.
///
/// Layout:
/// - Optional quick-prompt chip row (only when no messages and no attachments)
/// - Optional attachment thumbnail strip (80 pt thumbnails)
/// - A single visual "container" wrapping the text field on top and an
///   icon action row below (attach, voice, provider chip, thinking toggle,
///   spacer, char counter, send/stop).
struct ChatInputView: View {
    @Binding var text: String
    let isStreaming: Bool
    let attachments: [AIChatViewModel.Attachment]
    let hasMessages: Bool
    let quickPrompts: [String]
    let onSend: () -> Void
    let onStop: () -> Void
    let onAttach: () -> Void
    var onRemoveAttachment: (UUID) -> Void
    var onVoice: (() -> Void)? = nil
    var onProviderTap: (() -> Void)? = nil
    var onModelSettingsTap: (() -> Void)? = nil
    var onToggleThinking: (() -> Void)? = nil
    var thinkingEnabled: Bool = false
    var supportsThinking: Bool = false
    var currentProviderName: String = ""

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !hasMessages && attachments.isEmpty && !quickPrompts.isEmpty {
                quickPromptRow
            }

            if !attachments.isEmpty {
                AttachmentThumbnailStrip(
                    attachments: attachments,
                    onRemove: onRemoveAttachment
                )
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
            }

            inputContainer
        }
        .background(Morandi.background)
    }

    private var quickPromptRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(Array(quickPrompts.prefix(6)), id: \.self) { prompt in
                    Button {
                        text = prompt
                        focused = true
                    } label: {
                        Text(prompt)
                            .font(AppTypography.caption)
                            .foregroundStyle(Morandi.secondaryText)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .overlay(
                                Capsule()
                                    .stroke(Morandi.divider, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.md)
        }
        .padding(.vertical, AppSpacing.sm)
    }

    private var inputContainer: some View {
        VStack(spacing: AppSpacing.sm) {
            // Text input row
            HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("ai.input.placeholder")
                            .font(AppTypography.body)
                            .foregroundStyle(Morandi.tertiaryText)
                            .padding(.horizontal, AppSpacing.md + 4)
                            .padding(.vertical, AppSpacing.sm + 2)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(AppTypography.body)
                        .foregroundStyle(Morandi.primaryText)
                        .lineLimit(1...5)
                        .focused($focused)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                }
            }
            .padding(.top, AppSpacing.xs)

            // Actions row
            HStack(spacing: AppSpacing.md) {
                Button(action: onAttach) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 18))
                        .foregroundStyle(Morandi.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(isStreaming)

                if let onVoice {
                    Button(action: onVoice) {
                        Image(systemName: "mic")
                            .font(.system(size: 18))
                            .foregroundStyle(Morandi.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStreaming)
                }

                if let onProviderTap {
                    Button(action: onProviderTap) {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 14))
                            Text(currentProviderName)
                                .font(AppTypography.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(Morandi.secondaryText)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Morandi.elevatedBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if supportsThinking, let onToggleThinking {
                    Button(action: onToggleThinking) {
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.system(size: 13))
                            Text(thinkingEnabled ? "On" : "Off")
                                .font(AppTypography.caption2)
                                .lineLimit(1)
                        }
                        .foregroundStyle(thinkingEnabled ? Morandi.accent : Morandi.secondaryText)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(thinkingEnabled ? Morandi.accent.opacity(0.12) : Morandi.elevatedBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let onModelSettingsTap {
                    Button(action: onModelSettingsTap) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16))
                            .foregroundStyle(Morandi.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Character counter
                if text.count > 500 {
                    Text("\(text.count)")
                        .font(AppTypography.caption2)
                        .foregroundStyle(text.count > 4000 ? Morandi.destructive : Morandi.tertiaryText)
                }

                // Send / Stop button
                sendButton
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Morandi.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(focused ? Morandi.accent.opacity(0.3) : Morandi.divider, lineWidth: 1)
                )
                .ptShadow(level: 1)
        )
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.md)
        .animation(.easeInOut(duration: 0.2), value: focused)
    }

    @ViewBuilder
    private var sendButton: some View {
        if isStreaming {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Morandi.error))
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(text.isEmpty ? Morandi.warmGray : Morandi.accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty)
            .transition(.scale.combined(with: .opacity))
        }
    }
}
