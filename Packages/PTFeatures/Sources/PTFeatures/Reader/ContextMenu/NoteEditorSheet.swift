import SwiftUI
import PTCore
import PTReader
import PTUI

/// Sheet for creating or editing a reader annotation (highlight + note).
///
/// Displays the selected text read-only at the top, a color picker, a text
/// editor for the note body, and save/delete controls.
struct NoteEditorSheet: View {
    let selectedText: String
    let chapterTitle: String
    let existingNoteID: Int64?
    let onSave: (HighlightColor, String) -> Void
    let onDelete: (() -> Void)?
    let onDismiss: () -> Void

    @State private var highlightColor: HighlightColor
    @State private var noteText: String

    init(
        selectedText: String,
        chapterTitle: String,
        existingNoteID: Int64? = nil,
        initialColor: HighlightColor = .yellow,
        initialNote: String = "",
        onSave: @escaping (HighlightColor, String) -> Void,
        onDelete: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.selectedText = selectedText
        self.chapterTitle = chapterTitle
        self.existingNoteID = existingNoteID
        self.onSave = onSave
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        _highlightColor = State(initialValue: initialColor)
        _noteText = State(initialValue: initialNote)
    }

    private var isEditing: Bool { existingNoteID != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    selectionCard
                    colorSection
                    noteSection

                    if let onDelete {
                        deleteSection(onDelete)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(Morandi.background)
            .navigationTitle(isEditing ? "Edit Note" : "Add Note")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel"), action: onDismiss)
                        .foregroundStyle(Morandi.secondaryText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        onSave(highlightColor, noteText)
                    }
                    .foregroundStyle(Morandi.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Subviews

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if !chapterTitle.isEmpty {
                Text(chapterTitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
            }

            Text(selectedText)
                .font(AppTypography.body)
                .foregroundStyle(Morandi.primaryText)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                .fill(Morandi.cardBackground)
        )
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("reader.highlight_color")
                .font(AppTypography.headline)
                .foregroundStyle(Morandi.primaryText)

            HighlightColorPicker(
                selected: highlightColor,
                onSelect: { highlightColor = $0 }
            )
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("common.note")
                .font(AppTypography.headline)
                .foregroundStyle(Morandi.primaryText)

            TextEditor(text: $noteText)
                .frame(minHeight: 160)
                .padding(AppSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                        .fill(Morandi.cardBackground)
                )
                .overlay(alignment: .topLeading) {
                    if noteText.isEmpty {
                        Text("notes.write_thoughts")
                            .font(AppTypography.body)
                            .foregroundStyle(Morandi.tertiaryText)
                            .padding(.top, AppSpacing.sm)
                            .padding(.leading, AppSpacing.sm)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func deleteSection(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Text("reader.delete_annotation")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
