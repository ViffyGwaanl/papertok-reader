import SwiftUI
import PTAIServices
import PTUI

/// Lists past AI conversations with resume, delete, and new chat actions.
///
/// Each row shows title, date, message count, and a preview of the last message.
public struct ConversationListView: View {
    @State private var summaries: [ConversationPersistenceService.ConversationSummary] = []
    @State private var errorMessage: String?

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
        .onAppear { loadSummaries() }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(Morandi.tertiaryText)
            Text("No conversations yet")
                .font(AppTypography.title3)
                .foregroundStyle(Morandi.secondaryText)
            Button("Start a new chat") {
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
            ForEach(summaries) { summary in
                Button {
                    onSelect(summary.id)
                } label: {
                    ConversationRowView(summary: summary)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteSummaries)
        }
        .listStyle(.plain)
    }

    private func loadSummaries() {
        do {
            summaries = try persistenceService.listSummaries()
        } catch {
            errorMessage = error.localizedDescription
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

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
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

            Text("\(summary.messageCount) messages")
                .font(AppTypography.caption2)
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
