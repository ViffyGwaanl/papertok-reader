import SwiftUI
import PTCore
import PTReader
import PTUI

/// Lists all bookmarks for the current book and lets the reader jump to
/// any bookmark or delete one.
///
/// The view talks to `ReaderViewModel` which owns the underlying
/// `BookNoteDAO` and the rendered PDF document so we can resolve the
/// page index for each bookmark.
struct BookmarkManagerView: View {
    let viewModel: ReaderViewModel
    let database: AppDatabase
    let onJump: (BookNote) -> Void

    @State private var bookmarks: [BookNote] = []
    @State private var isLoading = true
    @State private var showExportSheet = false
    @State private var exportedText: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(Morandi.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if bookmarks.isEmpty {
                    ContentUnavailableView(
                        "No Bookmarks",
                        systemImage: "bookmark",
                        description: Text("Tap the bookmark icon while reading to save the current page.")
                    )
                } else {
                    List {
                        ForEach(bookmarks) { note in
                            Button {
                                onJump(note)
                                dismiss()
                            } label: {
                                row(for: note)
                            }
                            .listRowBackground(Morandi.background)
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Morandi.background)
            .navigationTitle("Bookmarks")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Morandi.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await addBookmarkAtCurrentPage() }
                    } label: {
                        Image(systemName: "bookmark.fill")
                    }
                    .foregroundStyle(Morandi.accent)
                    .accessibilityLabel("Add bookmark")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        Task { await exportHighlights() }
                    } label: {
                        Label("Export Highlights", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .task { await reload() }
            .sheet(isPresented: $showExportSheet) {
                exportSheet
            }
        }
    }

    private func row(for note: BookNote) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(Morandi.accent)
                Text(displayLocation(for: note))
                    .font(AppTypography.headline)
                    .foregroundStyle(Morandi.primaryText)
                Spacer()
                if let createTime = note.createTime {
                    Text(createTime, style: .date)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.tertiaryText)
                }
            }
            if !note.chapter.isEmpty {
                Text(note.chapter)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                    .lineLimit(1)
            }
            if let readerNote = note.readerNote, !readerNote.isEmpty {
                Text(readerNote)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayLocation(for note: BookNote) -> String {
        if let anchor = PDFAnnotationBridge.anchor(fromStoredString: note.cfi) {
            return anchor.pageLabel.isEmpty ? "Page \(anchor.pageIndex + 1)" : anchor.pageLabel
        }
        return note.content.isEmpty ? "Bookmark" : note.content
    }

    private func reload() async {
        isLoading = true
        bookmarks = await viewModel.loadBookmarks()
        isLoading = false
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.compactMap { bookmarks[$0].id }
        Task {
            for id in toDelete {
                await viewModel.deleteBookmark(id: id)
            }
            await reload()
        }
    }

    private func addBookmarkAtCurrentPage() async {
        await viewModel.toggleBookmark()
        await reload()
    }

    private func exportHighlights() async {
        guard let bookId = viewModel.book.id else { return }
        let service = HighlightExportService()
        do {
            exportedText = try await service.export(
                bookId: bookId,
                bookTitle: viewModel.book.title,
                format: .markdown,
                database: database
            )
            showExportSheet = true
        } catch {
            exportedText = "Failed to export: \(error.localizedDescription)"
            showExportSheet = true
        }
    }

    private var exportSheet: some View {
        NavigationStack {
            ScrollView {
                Text(exportedText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .background(Morandi.background)
            .navigationTitle("Exported")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showExportSheet = false }
                        .foregroundStyle(Morandi.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: exportedText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundStyle(Morandi.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
