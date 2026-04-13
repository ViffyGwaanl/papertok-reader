import SwiftUI
import PTUI

/// View for browsing and editing daily memory markdown files.
///
/// Displays the current day's memory content and allows viewing/editing past entries.
/// Memory files are stored as markdown in the memory directory.
public struct MemoryView: View {
    let memoryDirectory: URL

    @State private var selectedDate: Date = Date()
    @State private var content: String = ""
    @State private var isEditing = false
    @State private var isDirty = false
    @State private var memoryFiles: [MemoryFileInfo] = []
    @State private var searchText: String = ""
    @State private var errorMessage: String?

    public init(memoryDirectory: URL) {
        self.memoryDirectory = memoryDirectory
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Morandi.tertiaryText)
                TextField(String(localized: "ai.search_memories"), text: $searchText)
                    .font(AppTypography.body)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Morandi.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppSpacing.sm)
            .background(Morandi.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)

            if filteredFiles.isEmpty && !searchText.isEmpty {
                noSearchResults
            } else if memoryFiles.isEmpty {
                emptyState
            } else {
                memoryContent
            }
        }
        .background(Morandi.background)
        .navigationTitle(String(localized: "ai.memory"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: AppSpacing.sm) {
                    if isEditing {
                        Button(String(localized: "common.save")) { saveContent() }
                            .foregroundStyle(Morandi.accent)
                    }
                    Button {
                        isEditing.toggle()
                    } label: {
                        Image(systemName: isEditing ? "eye" : "pencil")
                            .foregroundStyle(Morandi.accent)
                    }
                }
            }
        }
        .onAppear { loadMemoryFiles(); loadContent(for: selectedDate) }
    }

    private var filteredFiles: [MemoryFileInfo] {
        guard !searchText.isEmpty else { return memoryFiles }
        let query = searchText.lowercased()
        return memoryFiles.filter {
            $0.filename.lowercased().contains(query) ||
            $0.preview.lowercased().contains(query)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(Morandi.tertiaryText)
            Text("ai.no_memories")
                .font(AppTypography.title3)
                .foregroundStyle(Morandi.secondaryText)
            Text("ai.memory_save_hint")
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)
            Button(String(localized: "ai.create_today_memory")) {
                createTodayMemory()
            }
            .buttonStyle(.borderedProminent)
            .tint(Morandi.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSearchResults: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Morandi.tertiaryText)
            Text("ai.no_matching_memories")
                .font(AppTypography.body)
                .foregroundStyle(Morandi.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var memoryContent: some View {
        HSplitOrVStack {
            // File list
            List(selection: Binding(
                get: { selectedFileId },
                set: { newId in
                    if let info = filteredFiles.first(where: { $0.id == newId }) {
                        selectFile(info)
                    }
                }
            )) {
                ForEach(filteredFiles) { file in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.displayName)
                            .font(AppTypography.caption.weight(.medium))
                            .foregroundStyle(Morandi.primaryText)
                        Text(file.preview)
                            .font(AppTypography.caption2)
                            .foregroundStyle(Morandi.secondaryText)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                    .tag(file.id)
                }
            }
            .listStyle(.plain)
            .frame(minWidth: 180)

            // Content editor/viewer
            VStack(spacing: 0) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.destructive)
                        .padding(AppSpacing.sm)
                }

                if isEditing {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .padding(AppSpacing.sm)
                        .scrollContentBackground(.hidden)
                        .background(Morandi.cardBackground)
                        .onChange(of: content) { _, _ in isDirty = true }
                } else {
                    ScrollView {
                        Text(markdownContent)
                            .font(AppTypography.body)
                            .foregroundStyle(Morandi.primaryText)
                            .padding(AppSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedFileId: String? {
        filteredFiles.first { $0.date == selectedDate }?.id
    }

    private var markdownContent: AttributedString {
        if let attributed = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(content)
    }

    // MARK: - File Operations

    private func loadMemoryFiles() {
        let fm = FileManager.default
        try? fm.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
        guard let files = try? fm.contentsOfDirectory(at: memoryDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        memoryFiles = files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> MemoryFileInfo? in
                let name = url.deletingPathExtension().lastPathComponent
                let date = dateFormatter.date(from: name) ?? Date.distantPast
                let preview = (try? String(contentsOf: url, encoding: .utf8).prefix(100)) ?? ""
                return MemoryFileInfo(
                    filename: url.lastPathComponent,
                    displayName: name,
                    date: date,
                    preview: String(preview),
                    url: url
                )
            }
            .sorted { $0.date > $1.date }
    }

    private func loadContent(for date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "\(formatter.string(from: date)).md"
        let url = memoryDirectory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: url.path) {
            content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        } else {
            content = ""
        }
        isDirty = false
    }

    private func saveContent() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "\(formatter.string(from: selectedDate)).md"
        let url = memoryDirectory.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            errorMessage = nil
            loadMemoryFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectFile(_ info: MemoryFileInfo) {
        if isDirty { saveContent() }
        selectedDate = info.date
        content = (try? String(contentsOf: info.url, encoding: .utf8)) ?? ""
        isDirty = false
    }

    private func createTodayMemory() {
        selectedDate = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        content = "# Memory - \(formatter.string(from: Date()))\n\n"
        isDirty = true
        saveContent()
    }
}

// MARK: - Supporting Types

struct MemoryFileInfo: Identifiable {
    let filename: String
    let displayName: String
    let date: Date
    let preview: String
    let url: URL

    var id: String { filename }
}

/// Layout helper: HSplitView on macOS, VStack on iOS.
struct HSplitOrVStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        HSplitView { content() }
        #else
        VStack(spacing: 0) { content() }
        #endif
    }
}
