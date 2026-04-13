#if canImport(SwiftUI)
import SwiftUI
import PTUI

/// A markdown-aware note editor with live preview.
///
/// Offers a segmented Edit/Preview toggle, a formatting toolbar with common
/// Markdown shortcuts (bold, italic, link, list, heading), a font size slider,
/// and Save / Cancel actions. Morandi-styled for PaperTok Reader.
public struct RichNoteEditorView: View {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case edit
        case preview

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .edit: return "Edit"
            case .preview: return "Preview"
            }
        }
    }

    @Binding private var text: String
    @State private var mode: Mode = .edit
    @State private var fontSize: Double = 16

    private let title: String
    private let onSave: (String) -> Void
    private let onCancel: () -> Void

    public init(
        text: Binding<String>,
        title: String = "Edit Note",
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._text = text
        self.title = title
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 12) {
            modeSegmented

            if mode == .edit {
                toolbar
                editor
            } else {
                preview
            }

            fontSlider
            actionBar
        }
        .padding(16)
        .background(Morandi.background.ignoresSafeArea())
    }

    // MARK: - Subviews

    private var modeSegmented: some View {
        Picker("Mode", selection: $mode) {
            ForEach(Mode.allCases) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("rich_note_editor_mode_picker")
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolbarButton(label: "B", systemImage: "bold") {
                wrapSelection(with: "**")
            }
            .fontWeight(.bold)

            toolbarButton(label: "I", systemImage: "italic") {
                wrapSelection(with: "*")
            }
            .italic()

            toolbarButton(label: "Link", systemImage: "link") {
                insertInline("[text](https://)")
            }

            toolbarButton(label: "List", systemImage: "list.bullet") {
                insertLinePrefix("- ")
            }

            toolbarButton(label: "H", systemImage: "textformat.size") {
                insertLinePrefix("# ")
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.system(size: fontSize))
            .foregroundStyle(Morandi.primaryText)
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(Morandi.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Morandi.divider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(minHeight: 200)
    }

    private var preview: some View {
        ScrollView {
            Text(renderedMarkdown)
                .font(.system(size: fontSize))
                .foregroundStyle(Morandi.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Morandi.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Morandi.divider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(minHeight: 200)
    }

    private var fontSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "textformat.size.smaller")
                .foregroundStyle(Morandi.secondaryText)
            Slider(value: $fontSize, in: 12...28, step: 1)
                .tint(Morandi.sage)
            Image(systemName: "textformat.size.larger")
                .foregroundStyle(Morandi.secondaryText)
            Text("\(Int(fontSize))")
                .font(.caption)
                .foregroundStyle(Morandi.secondaryText)
                .frame(width: 28, alignment: .trailing)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Text("common.cancel")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(Morandi.warmGray)

            Button {
                onSave(text)
            } label: {
                Text("common.save")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Morandi.sage)
        }
    }

    private func toolbarButton(
        label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 32, height: 32)
                .background(Morandi.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Morandi.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Markdown Rendering

    private var renderedMarkdown: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return attributed
        }
        return AttributedString(text)
    }

    // MARK: - Editing helpers

    private func wrapSelection(with delimiter: String) {
        text.append("\(delimiter)text\(delimiter)")
    }

    private func insertInline(_ snippet: String) {
        text.append(snippet)
    }

    private func insertLinePrefix(_ prefix: String) {
        if text.isEmpty || text.hasSuffix("\n") {
            text.append(prefix)
        } else {
            text.append("\n\(prefix)")
        }
    }
}

#Preview {
    StatefulPreviewWrapper("# Hello\n\nThis is a **note**.")
}

private struct StatefulPreviewWrapper: View {
    @State private var text: String
    init(_ initial: String) { _text = State(initialValue: initial) }
    var body: some View {
        RichNoteEditorView(text: $text, onSave: { _ in }, onCancel: {})
    }
}
#endif
