import SwiftUI
import PTCore
import PTUI

/// Editor for the user's customizable Quick Prompt list (used by the reader's
/// text-selection action menu). Supports add / delete / drag-reorder and
/// persists a JSON array to UserDefaults via SettingsViewModel.
public struct QuickPromptsEditorView: View {
    @State private var viewModel: SettingsViewModel
    @State private var prompts: [QuickPrompt] = []
    @State private var editingPrompt: QuickPrompt?
    @State private var showAdd = false

    @MainActor
    public init(viewModel: SettingsViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? SettingsViewModel())
    }

    public var body: some View {
        List {
            if prompts.isEmpty {
                Section {
                    Text("No quick prompts. Tap + to add one.")
                        .foregroundStyle(Morandi.secondaryText)
                }
            } else {
                Section("Prompts") {
                    ForEach(prompts) { prompt in
                        Button { editingPrompt = prompt } label: {
                            row(prompt)
                        }
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
                }
            }

            Section {
                Button {
                    editingPrompt = nil
                    showAdd = true
                } label: {
                    Label("Add Prompt", systemImage: "plus.circle")
                        .foregroundStyle(Morandi.accent)
                }

                Button("Restore Defaults") {
                    prompts = QuickPrompt.builtIn
                    persist()
                }
                .foregroundStyle(Morandi.accent)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Morandi.background)
        .navigationTitle(String(localized: "settings.quick_prompts"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        #endif
        .onAppear { prompts = viewModel.loadQuickPrompts() }
        .sheet(isPresented: $showAdd) {
            QuickPromptEditSheet(prompt: nil) { newPrompt in
                var p = prompts
                var added = newPrompt
                added.sortOrder = p.count
                p.append(added)
                prompts = p
                persist()
            }
        }
        .sheet(item: $editingPrompt) { prompt in
            QuickPromptEditSheet(prompt: prompt) { updated in
                if let idx = prompts.firstIndex(where: { $0.id == updated.id }) {
                    prompts[idx] = updated
                    persist()
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ prompt: QuickPrompt) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: prompt.iconName.isEmpty ? "sparkles" : prompt.iconName)
                .foregroundStyle(Morandi.accent)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Morandi.sage.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.title)
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(Morandi.primaryText)
                Text(prompt.promptText)
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.secondaryText)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func delete(at offsets: IndexSet) {
        prompts.remove(atOffsets: offsets)
        reindex()
        persist()
    }

    private func move(from source: IndexSet, to destination: Int) {
        prompts.move(fromOffsets: source, toOffset: destination)
        reindex()
        persist()
    }

    private func reindex() {
        for i in prompts.indices {
            prompts[i].sortOrder = i
        }
    }

    private func persist() {
        viewModel.saveQuickPrompts(prompts)
    }
}

// MARK: - Edit Sheet

struct QuickPromptEditSheet: View {
    let prompt: QuickPrompt?
    let onSave: (QuickPrompt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var promptText: String
    @State private var iconName: String

    private static let availableIcons = [
        "sparkles", "lightbulb", "text.justify.leading", "globe",
        "character.book.closed", "questionmark.circle", "quote.bubble",
        "pencil.and.outline", "translate", "wand.and.stars", "brain",
        "doc.text.magnifyingglass", "highlighter", "bookmark", "star",
    ]

    init(prompt: QuickPrompt?, onSave: @escaping (QuickPrompt) -> Void) {
        self.prompt = prompt
        self.onSave = onSave
        _title = State(initialValue: prompt?.title ?? "")
        _promptText = State(initialValue: prompt?.promptText ?? "")
        _iconName = State(initialValue: prompt?.iconName ?? "sparkles")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("e.g. Explain", text: $title)
                }
                Section {
                    TextEditor(text: $promptText)
                        .frame(minHeight: 120)
                        .font(AppTypography.body)
                } header: {
                    Text("Prompt Text")
                } footer: {
                    Text("Use {text} as a placeholder for the selected text.")
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.tertiaryText)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: AppSpacing.sm) {
                        ForEach(Self.availableIcons, id: \.self) { name in
                            Image(systemName: name)
                                .font(.system(size: 18))
                                .foregroundStyle(iconName == name ? Morandi.accent : Morandi.secondaryText)
                                .frame(width: 38, height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(iconName == name ? Morandi.sage.opacity(0.25) : Morandi.cardBackground)
                                )
                                .onTapGesture { iconName = name }
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle(prompt == nil ? "New Prompt" : "Edit Prompt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let updated = QuickPrompt(
                            id: prompt?.id ?? UUID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            promptText: promptText,
                            iconName: iconName,
                            sortOrder: prompt?.sortOrder ?? 0
                        )
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || promptText.isEmpty)
                }
            }
        }
    }
}
