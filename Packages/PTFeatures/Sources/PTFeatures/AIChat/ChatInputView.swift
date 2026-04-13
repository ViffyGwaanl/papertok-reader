import SwiftUI
import PTUI
#if os(iOS)
import UIKit
#endif

/// Chat input bar with text field, attachment picker, voice input, send button,
/// quick prompts, paste-image hint, and animated transitions.
struct ChatInputView: View {
    @Binding var text: String
    let isStreaming: Bool
    var hasMessages: Bool = false
    let quickPrompts: [QuickPrompt]
    let onSend: () -> Void
    let onAttach: () -> Void
    let onStop: () -> Void
    var onVoice: (() -> Void)? = nil
    var onPasteImage: (() -> Void)? = nil

    struct QuickPrompt: Identifiable {
        let id = UUID()
        let label: String
        let prompt: String
    }

    @FocusState private var isFocused: Bool
    @State private var pasteboardHasImage: Bool = false

    private var showQuickPrompts: Bool {
        text.isEmpty && !isFocused && !hasMessages && !quickPrompts.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if showQuickPrompts {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(quickPrompts) { prompt in
                            Button {
                                text = prompt.prompt
                                onSend()
                            } label: {
                                Text(prompt.label)
                                    .font(AppTypography.caption)
                                    .padding(.horizontal, AppSpacing.md)
                                    .padding(.vertical, AppSpacing.sm)
                                    .background(Capsule().fill(Morandi.cardBackground))
                                    .overlay(Capsule().strokeBorder(Morandi.divider, lineWidth: 0.5))
                                    .foregroundStyle(Morandi.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }
                .padding(.bottom, AppSpacing.sm)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if pasteboardHasImage && text.isEmpty {
                Button {
                    onPasteImage?()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste image from clipboard")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.accent)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                            .fill(Morandi.accent.opacity(0.08))
                    )
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xs)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            if text.count > 500 {
                HStack {
                    Spacer()
                    Text("\(text.count) chars")
                        .font(AppTypography.caption2)
                        .foregroundStyle(text.count > 4000 ? Morandi.destructive : Morandi.tertiaryText)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, 2)
            }

            HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                Button(action: onAttach) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20))
                        .foregroundStyle(Morandi.secondaryText)
                }
                .buttonStyle(.plain)

                if let onVoice {
                    Button(action: onVoice) {
                        Image(systemName: "mic")
                            .font(.system(size: 20))
                            .foregroundStyle(Morandi.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text("reader.ask_ai")
                            .foregroundStyle(Morandi.tertiaryText)
                            .font(AppTypography.body)
                            .padding(.leading, AppSpacing.xs)
                            .padding(.top, 8)
                    }
                    TextEditor(text: $text)
                        .font(AppTypography.body)
                        .foregroundStyle(Morandi.primaryText)
                        .frame(minHeight: 36, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                }
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, AppSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                        .fill(Morandi.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                        .strokeBorder(isFocused ? Morandi.accent.opacity(0.5) : Morandi.divider, lineWidth: 0.5)
                )
                .animation(.easeInOut(duration: 0.18), value: isFocused)

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Morandi.destructive)
                            .transition(.scale.combined(with: .opacity))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(text.isEmpty ? Morandi.tertiaryText : Morandi.accent)
                            .scaleEffect(text.isEmpty ? 0.92 : 1.0)
                            .opacity(text.isEmpty ? 0.7 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: text.isEmpty)
                    }
                    .buttonStyle(.plain)
                    .disabled(text.isEmpty)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
        }
        .animation(.easeInOut(duration: 0.2), value: showQuickPrompts)
        .animation(.easeInOut(duration: 0.2), value: pasteboardHasImage)
        .background(Morandi.background)
        .onAppear { updatePasteboard() }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            updatePasteboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            updatePasteboard()
        }
        #endif
    }

    private func updatePasteboard() {
        #if os(iOS)
        pasteboardHasImage = UIPasteboard.general.hasImages
        #endif
    }
}
