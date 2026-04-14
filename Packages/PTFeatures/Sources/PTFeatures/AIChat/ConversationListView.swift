import SwiftUI
import PTAIServices
import PTCore
import PTUI

/// Lists past AI conversations with resume, delete, and new chat actions.
///
/// Each row shows title, date, message count, and a preview of the last message.
public struct ConversationListView: View {
    @State private var summaries: [ConversationPersistenceService.ConversationSummary] = []
    @State private var pinnedIds: Set<String> = []
    @State private var searchText: String = ""
    @State private var errorMessage: String?
    @State private var renameTarget: ConversationPersistenceService.ConversationSummary?
    @State private var renameText: String = ""
    @State private var exportItem: ExportItem?

    private let pinnedKey = "papertok.ai.pinnedConversations"

    let persistenceService: ConversationPersistenceService
    let onSelect: (String) -> Void
    let onNewChat: () -> Void

    public init(
        persistenceService: ConversationPersistenceService,
        onSelect: @escaping (String) -> Void,
        onNewChat: @escaping () -> Void
    ) {
        self.persistenceService = persistenceService
        self.onSelect = onSelect
        self.onNewChat = onNewChat
    }

    public var body: some View {
        Group {
            if summaries.isEmpty {
                emptyState
            } else {
                conversationList
            }
        }
        .navigationTitle(String(localized: "ai.conversations"))
        .toolbar {
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
            text: $searchText,
            placement: .automatic,
            prompt: AppLocalization.string("ai.search_conversations")
        )
        .onAppear {
            loadPinned()
            loadSummaries()
        }
        .sheet(item: $renameTarget) { target in
            renameSheet(for: target)
        }
        #if os(iOS)
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.url])
        }
        #endif
    }

    // MARK: - Sections (date grouping + pinned)

    private struct SectionGroup {
        let title: String
        let isPinned: Bool
        let items: [ConversationPersistenceService.ConversationSummary]
    }

    private var filteredSummaries: [ConversationPersistenceService.ConversationSummary] {
        guard searchText.isEmpty == false else { return summaries }
        let query = searchText.lowercased()
        return summaries.filter {
            $0.title.lowercased().contains(query) ||
            $0.lastMessagePreview.lowercased().contains(query)
        }
    }

    private var sections: [SectionGroup] {
        let items = filteredSummaries
        let pinned = items.filter { pinnedIds.contains($0.id) }
        let rest = items.filter { !pinnedIds.contains($0.id) }
        var result: [SectionGroup] = []
        if !pinned.isEmpty {
            result.append(
                SectionGroup(
                    title: AppLocalization.string("ai.conversations.pinned"),
                    isPinned: true,
                    items: pinned
                )
            )
        }
        let cal = Calendar.current
        let now = Date()
        var today: [ConversationPersistenceService.ConversationSummary] = []
        var yesterday: [ConversationPersistenceService.ConversationSummary] = []
        var thisWeek: [ConversationPersistenceService.ConversationSummary] = []
        var earlier: [ConversationPersistenceService.ConversationSummary] = []
        for item in rest {
            if cal.isDateInToday(item.updatedAt) { today.append(item) }
            else if cal.isDateInYesterday(item.updatedAt) { yesterday.append(item) }
            else if let week = cal.dateInterval(of: .weekOfYear, for: now), week.contains(item.updatedAt) { thisWeek.append(item) }
            else { earlier.append(item) }
        }
        if !today.isEmpty {
            result.append(SectionGroup(title: AppLocalization.string("common.today"), isPinned: false, items: today))
        }
        if !yesterday.isEmpty {
            result.append(SectionGroup(title: AppLocalization.string("common.yesterday"), isPinned: false, items: yesterday))
        }
        if !thisWeek.isEmpty {
            result.append(SectionGroup(title: AppLocalization.string("common.this_week"), isPinned: false, items: thisWeek))
        }
        if !earlier.isEmpty {
            result.append(SectionGroup(title: AppLocalization.string("common.earlier"), isPinned: false, items: earlier))
        }
        return result
    }

    @ViewBuilder
    private func renameSheet(for target: ConversationPersistenceService.ConversationSummary) -> some View {
        NavigationStack {
            Form {
                TextField(AppLocalization.string("common.title"), text: $renameText)
            }
            .navigationTitle(AppLocalization.string("common.rename"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("common.cancel")) { renameTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("common.save")) { performRename(target) }.bold()
                }
            }
        }
        .presentationDetents([.height(200)])
    }

    private func togglePin(_ id: String) {
        if pinnedIds.contains(id) { pinnedIds.remove(id) } else { pinnedIds.insert(id) }
        savePinned()
    }

    private func performRename(_ target: ConversationPersistenceService.ConversationSummary) {
        defer { renameTarget = nil }
        let newTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else { return }
        if var loaded = try? persistenceService.load(id: target.id) {
            loaded.title = newTitle
            loaded.updatedAt = Date()
            try? persistenceService.save(loaded)
            loadSummaries()
        }
    }

    private func export(_ summary: ConversationPersistenceService.ConversationSummary) {
        guard let loaded = try? persistenceService.load(id: summary.id) else { return }
        var md = "# \(loaded.title)\n\n"
        for msg in loaded.tree.activeMessages() {
            guard let text = msg.textContent, !text.isEmpty else { continue }
            switch msg.role {
            case .system:
                md += "> _\(AppLocalization.string("ai.role.system")): \(text)_\n\n"
            case .user:
                md += "**\(AppLocalization.string("ai.role.user")):** \(text)\n\n"
            case .assistant:
                md += "**\(AppLocalization.string("ai.role.assistant")):** \(text)\n\n"
            case .tool: md += "```\n\(text)\n```\n\n"
            }
        }
        let safeName = loaded.title.replacingOccurrences(of: "/", with: "_")
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).md")
        try? md.write(to: tmp, atomically: true, encoding: .utf8)
        exportItem = ExportItem(url: tmp)
    }

    private func loadPinned() {
        if let data = UserDefaults.standard.array(forKey: pinnedKey) as? [String] {
            pinnedIds = Set(data)
        }
    }

    private func savePinned() {
        UserDefaults.standard.set(Array(pinnedIds), forKey: pinnedKey)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(Morandi.tertiaryText)
            Text("ai.no_conversations")
                .font(AppTypography.title3)
                .foregroundStyle(Morandi.secondaryText)
            Button(String(localized: "ai.start_chat")) {
                onNewChat()
            }
            .buttonStyle(.borderedProminent)
            .tint(Morandi.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var conversationList: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.items) { summary in
                        Button {
                            onSelect(summary.id)
                        } label: {
                            ConversationRowView(
                                summary: summary,
                                isPinned: pinnedIds.contains(summary.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                togglePin(summary.id)
                            } label: {
                                Label(
                                    pinnedIds.contains(summary.id)
                                        ? AppLocalization.string("ai.unpin_conversation")
                                        : AppLocalization.string("ai.pin_conversation"),
                                    systemImage: pinnedIds.contains(summary.id) ? "pin.slash" : "pin"
                                )
                            }
                            .tint(Morandi.accent)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                try? persistenceService.delete(id: summary.id)
                                summaries.removeAll { $0.id == summary.id }
                                pinnedIds.remove(summary.id)
                                savePinned()
                            } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                            Button {
                                renameText = summary.title
                                renameTarget = summary
                            } label: {
                                Label("common.rename", systemImage: "pencil")
                            }
                            .tint(Morandi.clay)
                            Button {
                                export(summary)
                            } label: {
                                Label("ai.conversation.export", systemImage: "square.and.arrow.up")
                            }
                            .tint(Morandi.powder)
                        }
                        .contextMenu {
                            Button {
                                togglePin(summary.id)
                            } label: {
                                Label(
                                    pinnedIds.contains(summary.id)
                                        ? AppLocalization.string("ai.unpin_conversation")
                                        : AppLocalization.string("ai.pin_conversation"),
                                    systemImage: pinnedIds.contains(summary.id) ? "pin.slash" : "pin"
                                )
                            }
                            Button {
                                renameText = summary.title
                                renameTarget = summary
                            } label: {
                                Label("common.rename", systemImage: "pencil")
                            }
                            Button {
                                export(summary)
                            } label: {
                                Label("ai.conversation.export_markdown", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        if section.isPinned {
                            Image(systemName: "pin.fill").font(.caption2)
                        }
                        Text(section.title)
                    }
                    .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.plain)
        #endif
    }

    private func loadSummaries() {
        do {
            summaries = try persistenceService.listSummaries()
        } catch {
            errorMessage = AppLocalization.localizedErrorDescription(error)
                ?? AppLocalization.string("common.failed_to_load")
        }
    }

    private func deleteSummaries(at offsets: IndexSet) {
        for index in offsets {
            let summary = summaries[index]
            try? persistenceService.delete(id: summary.id)
        }
        summaries.remove(atOffsets: offsets)
    }
}

/// A single row in the conversation list.
struct ConversationRowView: View {
    let summary: ConversationPersistenceService.ConversationSummary
    var isPinned: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: 4) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Morandi.accent)
                }
                Text(summary.title)
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(Morandi.primaryText)
                    .lineLimit(1)
                Spacer()
                Text(formattedDate)
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.tertiaryText)
            }

            if !summary.lastMessagePreview.isEmpty {
                Text(summary.lastMessagePreview)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                    .lineLimit(2)
            }

            HStack(spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 9))
                Text("\(summary.messageCount)")
                    .font(AppTypography.caption2)
            }
            .foregroundStyle(Morandi.tertiaryText)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: summary.updatedAt, relativeTo: Date())
    }
}

// MARK: - Export Helpers

struct ExportItem: Identifiable {
    var id: String { url.path }
    let url: URL
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
