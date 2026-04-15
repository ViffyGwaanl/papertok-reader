import SwiftUI
import PTAIServices
import PTCore
import PTUI

/// Lists past AI conversations with filter chips, search, pin/rename/delete/export actions.
public struct ConversationListView: View {
    @State private var viewModel: ConversationListViewModel
    private let currentBookId: String?
    private let onSelect: (String) -> Void
    private let onNewChat: () -> Void

    @State private var renameTargetId: String?
    @State private var renameText: String = ""
    @State private var renameErrorVisible: Bool = false
    @State private var deleteTargetId: String?
    @State private var exportSourceId: String?
    @State private var exportedFileURL: URL?
    @State private var didBootstrap: Bool = false
    @Environment(\.dismiss) private var dismiss

    public init(
        viewModel: ConversationListViewModel,
        currentBookId: String? = nil,
        onSelect: @escaping (String) -> Void,
        onNewChat: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.currentBookId = currentBookId
        self.onSelect = onSelect
        self.onNewChat = onNewChat
    }

    public var body: some View {
        content
            .navigationTitle(String(localized: "ai.conversations"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker(String(localized: "chat.conversations.sort.last_used"), selection: sortBinding) {
                            Text("chat.conversations.sort.last_used").tag(ConversationListSortMode.lastUsed)
                            Text("chat.conversations.sort.created").tag(ConversationListSortMode.created)
                            Text("chat.conversations.sort.title").tag(ConversationListSortMode.title)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundStyle(Morandi.accent)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onNewChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Morandi.accent)
                    }
                }
            }
            .searchable(
                text: searchBinding,
                placement: .automatic,
                prompt: Text("chat.conversations.search_placeholder")
            )
            .task {
                if didBootstrap == false {
                    didBootstrap = true
                    if let bookId = currentBookId {
                        viewModel.setBookFilter(.book(id: bookId))
                    } else {
                        viewModel.setBookFilter(.all)
                    }
                    await viewModel.refresh()
                }
            }
            .alert(
                String(localized: "chat.conversations.rename.title"),
                isPresented: renameAlertBinding
            ) {
                TextField("chat.conversations.rename.placeholder", text: $renameText)
                Button("common.cancel", role: .cancel) { renameTargetId = nil }
                Button("common.save") {
                    guard let id = renameTargetId else { return }
                    let title = renameText
                    renameTargetId = nil
                    Task {
                        do {
                            try await viewModel.rename(id: id, to: title)
                        } catch {
                            renameErrorVisible = true
                        }
                    }
                }
            }
            .alert(
                String(localized: "chat.conversations.rename.error_empty"),
                isPresented: $renameErrorVisible
            ) {
                Button("common.ok", role: .cancel) { }
            }
            .confirmationDialog(
                String(localized: "chat.conversations.delete.confirm.title"),
                isPresented: deleteAlertBinding,
                titleVisibility: .visible
            ) {
                Button("chat.conversations.action.delete", role: .destructive) {
                    guard let id = deleteTargetId else { return }
                    deleteTargetId = nil
                    Task { try? await viewModel.delete(id: id) }
                }
                Button("common.cancel", role: .cancel) { deleteTargetId = nil }
            } message: {
                Text("chat.conversations.delete.confirm.message")
            }
            .confirmationDialog(
                String(localized: "chat.conversations.action.export"),
                isPresented: exportDialogBinding,
                titleVisibility: .visible
            ) {
                Button("chat.conversations.export.format.markdown") {
                    performExport(format: .markdown)
                }
                Button("chat.conversations.export.format.json") {
                    performExport(format: .json)
                }
                Button("common.cancel", role: .cancel) { exportSourceId = nil }
            }
            .sheet(isPresented: exportedFileSheetBinding) {
                if let url = exportedFileURL {
                    exportShareSheet(url: url)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            filterChipRow
            if viewModel.conversations.isEmpty {
                emptyState
            } else {
                listBody
            }
        }
    }

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                chip(
                    labelKey: "chat.conversations.filter.all",
                    isActive: viewModel.bookFilter == .all
                ) {
                    viewModel.setBookFilter(.all)
                }
                chip(
                    labelKey: "chat.conversations.filter.global",
                    isActive: viewModel.bookFilter == .global
                ) {
                    viewModel.setBookFilter(.global)
                }
                if let currentBookId {
                    chip(
                        labelKey: "chat.conversations.filter.this_book",
                        isActive: viewModel.bookFilter == .book(id: currentBookId)
                    ) {
                        viewModel.setBookFilter(.book(id: currentBookId))
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    @ViewBuilder
    private func chip(labelKey: String.LocalizationValue, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(String(localized: labelKey))
                .font(AppTypography.caption.weight(.medium))
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(
                    Capsule().fill(isActive ? Morandi.accent.opacity(0.2) : Color.clear)
                )
                .overlay(
                    Capsule().stroke(isActive ? Morandi.accent : Morandi.tertiaryText, lineWidth: 1)
                )
                .foregroundStyle(isActive ? Morandi.accent : Morandi.secondaryText)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(Morandi.tertiaryText)
            Text("chat.conversations.empty.title")
                .font(AppTypography.title3)
                .foregroundStyle(Morandi.secondaryText)
            Text("chat.conversations.empty.body")
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.tertiaryText)
            Button(String(localized: "chat.conversations.empty.action")) {
                onNewChat()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Morandi.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var listBody: some View {
        let pinned = viewModel.conversations.filter { $0.isPinned }
        let rest = viewModel.conversations.filter { !$0.isPinned }
        List {
            if viewModel.pinnedFirst && pinned.isEmpty == false {
                Section {
                    ForEach(pinned) { item in row(for: item) }
                } header: {
                    Text("chat.conversations.section.pinned")
                        .foregroundStyle(Morandi.secondaryText)
                }
                Section {
                    ForEach(rest) { item in row(for: item) }
                } header: {
                    Text("chat.conversations.section.recent")
                        .foregroundStyle(Morandi.secondaryText)
                }
            } else {
                ForEach(viewModel.conversations) { item in row(for: item) }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.plain)
        #endif
    }

    @ViewBuilder
    private func row(for item: ConversationListItem) -> some View {
        Button {
            onSelect(item.id)
        } label: {
            ConversationRowView(item: item)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameText = item.title
                renameTargetId = item.id
            } label: {
                Label("chat.conversations.action.rename", systemImage: "pencil")
            }
            Button {
                Task { try? await viewModel.togglePin(id: item.id) }
            } label: {
                if item.isPinned {
                    Label("chat.conversations.action.unpin", systemImage: "pin.slash")
                } else {
                    Label("chat.conversations.action.pin", systemImage: "pin")
                }
            }
            Button {
                exportSourceId = item.id
            } label: {
                Label("chat.conversations.action.export", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                deleteTargetId = item.id
            } label: {
                Label("chat.conversations.action.delete", systemImage: "trash")
            }
        }
    }

    private func performExport(format: ConversationExportFormat) {
        guard let id = exportSourceId else { return }
        exportSourceId = nil
        Task {
            if let url = try? await viewModel.export(id: id, format: format) {
                exportedFileURL = url
            }
        }
    }

    // MARK: - Bindings

    private var searchBinding: Binding<String> {
        Binding(
            get: { viewModel.searchQuery },
            set: { viewModel.setSearchQuery($0) }
        )
    }

    private var sortBinding: Binding<ConversationListSortMode> {
        Binding(
            get: { viewModel.sortMode },
            set: { viewModel.setSortMode($0) }
        )
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTargetId != nil },
            set: { if !$0 { renameTargetId = nil } }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteTargetId != nil },
            set: { if !$0 { deleteTargetId = nil } }
        )
    }

    private var exportDialogBinding: Binding<Bool> {
        Binding(
            get: { exportSourceId != nil },
            set: { if !$0 { exportSourceId = nil } }
        )
    }

    private var exportedFileSheetBinding: Binding<Bool> {
        Binding(
            get: { exportedFileURL != nil },
            set: { if !$0 { exportedFileURL = nil } }
        )
    }

    @ViewBuilder
    private func exportShareSheet(url: URL) -> some View {
        #if os(iOS)
        ExportShareSheet(items: [url])
        #else
        VStack(spacing: AppSpacing.md) {
            Text(url.lastPathComponent)
                .font(AppTypography.body)
            ShareLink(item: url) {
                Label("chat.conversations.action.export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        #endif
    }
}

/// A single row in the rewritten conversation list.
struct ConversationRowView: View {
    let item: ConversationListItem

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: 4) {
                Text(item.title)
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(Morandi.primaryText)
                    .lineLimit(1)
                Spacer()
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Morandi.accent)
                }
            }
            if item.snippet.isEmpty == false {
                Text(item.snippet)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(item.updatedAt, format: .relative(presentation: .named))
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.tertiaryText)
                Text(verbatim: "·")
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.tertiaryText)
                HStack(spacing: 2) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 9))
                    Text("\(item.messageCount)")
                        .font(AppTypography.caption2)
                }
                .foregroundStyle(Morandi.tertiaryText)
                if item.bookId != nil {
                    Image(systemName: "book.closed")
                        .font(.system(size: 9))
                        .foregroundStyle(Morandi.tertiaryText)
                        .accessibilityLabel(Text("chat.conversations.book_indicator.tooltip"))
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

#if os(iOS)
private struct ExportShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
