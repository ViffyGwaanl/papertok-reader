import SwiftUI
import PTUI

/// Chat input bar with text field, attachment picker, send button, and quick prompt chips.
///
/// Matches Flutter AiChatStream input row behavior:
/// - Multi-line text field (max 5 lines before scroll)
/// - Paperclip icon opens attachment picker
/// - Send disabled while streaming
/// - Quick prompt chips shown when input is empty
struct ChatInputView: View {
    @Binding var text: String
    let isStreaming: Bool
    let quickPrompts: [QuickPrompt]
    let onSend: () -> Void
    let onAttach: () -> Void
    let onStop: () -> Void

    struct QuickPrompt: Identifiable {
        let id = UUID()
        let label: String
        let prompt: String
    }

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Quick prompts (shown only when text is empty + not focused)
            if text.isEmpty && !isFocused && !quickPrompts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(quickPrompts) { prompt in
                            Button(prompt.label) {
                                text = prompt.prompt
                                onSend()
                            }
                            .font(AppTypography.caption)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(
                                Capsule()
                                    .fill(Morandi.cardBackground)
                                    .strokeBorder(Morandi.divider, lineWidth: 0.5)
                            )
                            .foregroundStyle(Morandi.secondaryText)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }
                .padding(.bottom, AppSpacing.sm)
            }

            // Input row
            HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                Button(action: onAttach) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20))
                        .foregroundStyle(Morandi.secondaryText)
                }
                .buttonStyle(.plain)

                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text("Ask AI...")
                            .foregroundStyle(Morandi.tertiaryText)
                            .font(AppTypography.body)
                            .padding(.leading, AppSpacing.xs)
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

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Morandi.destructive)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(text.isEmpty ? Morandi.tertiaryText : Morandi.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(text.isEmpty)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
        }
        .background(Morandi.background)
    }
}
