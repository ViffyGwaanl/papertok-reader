import SwiftUI

/// Sheet presented when the user long-presses a user message and taps Edit.
///
/// Offers a simple multi-line editor for the message text. Confirmation
/// routes the new draft back through the host view's `onSend` handler which
/// in turn triggers `AIChatViewModel.editAndResend(...)`.
public struct MessageEditSheet: View {
    let originalText: String
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var draft: String
    @Environment(\.dismiss) private var dismiss

    public init(
        originalText: String,
        onSend: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.originalText = originalText
        self.onSend = onSend
        self.onCancel = onCancel
        self._draft = State(initialValue: originalText)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft)
                        .frame(minHeight: 160)
                        .autocorrectionDisabled(false)
                }
            }
            .navigationTitle(Text("chat.message.edit.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("chat.message.edit.send_button") {
                        onSend(draft)
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
