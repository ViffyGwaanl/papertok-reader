import SwiftUI

/// A styled input container used for chat composer, note editor, etc.
/// Bottom-anchored with a text input area + action button row.
public struct PTComposerShell: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    let onSend: () -> Void
    let isSendDisabled: Bool

    public init(
        text: Binding<String>,
        placeholder: LocalizedStringKey,
        onSend: @escaping () -> Void,
        isSendDisabled: Bool = false
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onSend = onSend
        self.isSendDisabled = isSendDisabled
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.sm) {
            TextField(placeholder, text: $text, axis: .vertical)
                .font(AppTypography.body)
                .foregroundStyle(Morandi.primaryText)
                .lineLimit(1...5)
                .padding(AppSpacing.md)
                .background(Morandi.elevatedBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))

            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(AppTypography.title2)
                    .foregroundStyle(isSendDisabled ? Morandi.tertiaryText : Morandi.accent)
            }
            .buttonStyle(.plain)
            .disabled(isSendDisabled)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background(Morandi.cardBackground)
    }
}

// MARK: - Test Hooks

extension PTComposerShell {
    struct TestHooks {
        let isSendDisabled: Bool
        let currentText: String
    }

    var testHooks: TestHooks {
        TestHooks(isSendDisabled: isSendDisabled, currentText: text)
    }
}
