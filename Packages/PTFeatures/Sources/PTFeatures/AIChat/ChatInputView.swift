import SwiftUI
import PTUI
import UniformTypeIdentifiers
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
    /// W6.2 (E) — the mic button is hidden unless the host wires a real
    /// handler. We do NOT render the affordance when `onVoice` is nil because
    /// the app has no `NSSpeechRecognitionUsageDescription` yet; showing a
    /// disabled mic would be worse than showing nothing.
    var onVoice: (() -> Void)? = nil
    var onProviderTap: (() -> Void)? = nil
    /// W6.2 — short-tap on the secondary model chip opens the in-chat model
    /// picker sheet (`InChatModelPickerSheet`). When nil the chip is hidden.
    var onModelTap: (() -> Void)? = nil
    var onModelSettingsTap: (() -> Void)? = nil
    var onToggleThinking: (() -> Void)? = nil
    /// W6.2 (D) — clipboard image paste hook. When the host wires this, the
    /// composer listens for `.onPasteCommand(of: [.image])` and forwards the
    /// decoded image data back to the view model as a new attachment.
    var onPasteImage: ((Data) -> Void)? = nil
    var thinkingEnabled: Bool = false
    var supportsThinking: Bool = false
    var currentProviderName: String = ""
    /// Display name of the currently-selected model. Shown after the provider
    /// name in the read-only chip. When empty, only the provider name renders.
    var currentModelName: String = ""

    @FocusState private var focused: Bool

    /// Text rendered inside the provider chip. When both provider + model
    /// names are available, render "Provider · Model" so users can see which
    /// model will actually be used. Otherwise fall back to whichever is set.
    private var providerChipLabel: String {
        if currentProviderName.isEmpty == false,
           currentModelName.isEmpty == false,
           currentProviderName != currentModelName {
            return "\(currentProviderName) · \(currentModelName)"
        }
        return currentProviderName.isEmpty ? currentModelName : currentProviderName
    }

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
                        Text("ai.chat.placeholder")
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
                        // W6.2 (A) — hardware keyboard: ↩ sends, Shift+↩ still
                        // produces a newline because `.vertical` axis honours
                        // the modifier. iOS soft-keyboard honours the send
                        // label too, matching Flutter main.
                        .submitLabel(.send)
                        .onSubmit {
                            guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
                            onSend()
                        }
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
                            Text(currentProviderName.isEmpty ? providerChipLabel : currentProviderName)
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
                    .accessibilityLabel(Text(providerChipLabel))
                    .accessibilityHint(Text("chat.provider.chip.tooltip"))
                    .accessibilityAddTraits(.isButton)
                }

                // W6.2 — secondary model chip. Short-tap opens the in-chat
                // model picker sheet. The provider chip to the left still
                // routes to Settings → AI Provider Center for full config.
                if let onModelTap, currentModelName.isEmpty == false {
                    Button(action: onModelTap) {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.horizontal")
                                .font(.system(size: 12))
                            Text(currentModelName)
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
                    .accessibilityLabel(Text(currentModelName))
                    .accessibilityHint(Text("chat.input.model_picker.title"))
                    .accessibilityAddTraits(.isButton)
                }

                if supportsThinking, let onToggleThinking {
                    Button(action: onToggleThinking) {
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.system(size: 13))
                            Text(thinkingEnabled ? "common.enabled" : "common.off")
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
        .modifier(PasteImageModifier(onPasteImage: onPasteImage))
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
            // W6.2 (A) — global ⌘↩ shortcut. Works across iPad, macOS, and
            // iPhone with a hardware keyboard. SwiftUI dedupes against the
            // `.onSubmit` wired on the TextField, so there's no double-fire.
            .keyboardShortcut(.return, modifiers: .command)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

/// W6.2 (D) — clipboard image paste.
///
/// `.onPasteCommand` is macOS-only; on iOS the system's keyboard paste
/// affordance already routes text through the `TextField`. When a richer
/// iOS paste UX lands, this modifier can be extended behind the same hook.
private struct PasteImageModifier: ViewModifier {
    let onPasteImage: ((Data) -> Void)?

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onPasteCommand(of: [UTType.image.identifier]) { providers in
            handlePastedProviders(providers)
        }
        #else
        content
        #endif
    }

    #if os(macOS)
    private func handlePastedProviders(_ providers: [NSItemProvider]) {
        guard let onPasteImage else { return }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else { return }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            Task { @MainActor in
                onPasteImage(data)
            }
        }
    }
    #endif
}
