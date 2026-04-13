import SwiftUI
import PTCore
import PTReader
import PTUI

public struct EPUBReaderAnnotationDraft: Identifiable, Equatable, Sendable {
    public let id: String
    public var noteID: Int64?
    public var locatorString: String
    public var selectedText: String
    public var chapterTitle: String
    public var type: NoteType
    public var color: HighlightColor
    public var readerNote: String

    public init(
        noteID: Int64? = nil,
        locatorString: String,
        selectedText: String,
        chapterTitle: String,
        type: NoteType = .highlight,
        color: HighlightColor = .yellow,
        readerNote: String = ""
    ) {
        self.id = noteID.map { "note-\($0)" } ?? UUID().uuidString
        self.noteID = noteID
        self.locatorString = locatorString
        self.selectedText = selectedText
        self.chapterTitle = chapterTitle
        self.type = type
        self.color = color
        self.readerNote = readerNote
    }

    public init(note: BookNote) {
        let noteType = NoteType(rawValue: note.type) ?? .highlight
        self.init(
            noteID: note.id,
            locatorString: note.cfi,
            selectedText: noteType == .bookmark ? "" : note.content,
            chapterTitle: note.chapter,
            type: noteType,
            color: HighlightColor(databaseValue: note.color),
            readerNote: note.readerNote ?? ""
        )
    }

    public var isEditing: Bool {
        noteID != nil
    }
}

public struct EPUBReaderAnnotationEditorView: View {
    @Binding private var draft: EPUBReaderAnnotationDraft
    private let onSave: () -> Void
    private let onDelete: (() -> Void)?
    private let onCancel: () -> Void

    public init(
        draft: Binding<EPUBReaderAnnotationDraft>,
        onSave: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self._draft = draft
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    selectionCard
                    typeSection
                    colorSection
                    if draft.type == .note {
                        noteSection
                    }
                    if isSaveDisabled {
                        Text("reader.text_required")
                            .font(AppTypography.caption)
                            .foregroundStyle(Morandi.secondaryText)
                    }
                    if onDelete != nil {
                        deleteSection
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(Morandi.background)
            .navigationTitle(String(localized: draft.isEditing ? "reader.annotation.edit" : "reader.annotation.add"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel"), action: onCancel)
                        .foregroundStyle(Morandi.secondaryText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.isEditing ? String(localized: "common.save") : String(localized: "common.add"), action: onSave)
                        .foregroundStyle(Morandi.accent)
                        .disabled(isSaveDisabled)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(draft.chapterTitle.isEmpty ? String(localized: "reader.current_location") : draft.chapterTitle)
                .font(AppTypography.headline)
                .foregroundStyle(Morandi.primaryText)

            if draft.selectedText.isEmpty {
                Text("reader.bookmark_save_hint")
                    .font(AppTypography.body)
                    .foregroundStyle(Morandi.secondaryText)
            } else {
                Text(draft.selectedText)
                    .font(AppTypography.body)
                    .foregroundStyle(Morandi.primaryText)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Morandi.cardBackground)
        )
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("common.type")
                .font(AppTypography.headline)
                .foregroundStyle(Morandi.primaryText)

            Picker(String(localized: "common.type"), selection: $draft.type) {
                Text("reader.highlight").tag(NoteType.highlight)
                Text("reader.bookmark").tag(NoteType.bookmark)
                Text("common.note").tag(NoteType.note)
            }
            .pickerStyle(.segmented)
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("common.color")
                .font(AppTypography.headline)
                .foregroundStyle(Morandi.primaryText)

            HStack(spacing: AppSpacing.sm) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button {
                        draft.color = color
                    } label: {
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if draft.color == color {
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: 2)
                                        .padding(2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(color.accessibilityTitle))
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("reader.markdown_note")
                .font(AppTypography.headline)
                .foregroundStyle(Morandi.primaryText)

            TextEditor(text: $draft.readerNote)
                .frame(minHeight: 180)
                .padding(AppSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Morandi.cardBackground)
                )
                .overlay(alignment: .topLeading) {
                    if draft.readerNote.isEmpty {
                        Text("notes.capture_insight")
                            .font(AppTypography.body)
                            .foregroundStyle(Morandi.secondaryText)
                            .padding(.top, AppSpacing.sm)
                            .padding(.leading, AppSpacing.sm)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var isSaveDisabled: Bool {
        let trimmedSelection = draft.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft.type != .bookmark && trimmedSelection.isEmpty
    }

    @ViewBuilder
    private var deleteSection: some View {
        if let onDelete {
            Button(role: .destructive, action: onDelete) {
                Text("reader.delete_annotation")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

private extension HighlightColor {
    var accessibilityTitle: String {
        switch self {
        case .yellow: String(localized: "common.color.yellow")
        case .red: String(localized: "common.color.red")
        case .blue: String(localized: "common.color.blue")
        case .green: String(localized: "common.color.green")
        case .purple: String(localized: "common.color.purple")
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .yellow:
            Color(red: 1.0, green: 0.92, blue: 0.23)
        case .red:
            Color(red: 0.96, green: 0.27, blue: 0.21)
        case .blue:
            Color(red: 0.13, green: 0.59, blue: 0.95)
        case .green:
            Color(red: 0.30, green: 0.69, blue: 0.31)
        case .purple:
            Color(red: 0.61, green: 0.15, blue: 0.69)
        }
    }
}
