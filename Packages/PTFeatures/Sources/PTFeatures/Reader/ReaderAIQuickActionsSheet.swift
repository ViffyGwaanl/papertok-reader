import SwiftUI
import PTCore
import PTUI

/// Quick AI actions sheet accessible from the reader when text is selected.
/// Provides one-tap "Explain", "Translate", "Summarize" actions that pre-fill
/// the AI chat with context-aware prompts and open the AI panel.
public struct ReaderAIQuickActionsSheet: View {
    public let selectedText: String
    public let chapterTitle: String
    public let bookTitle: String
    private let onAction: (ReaderAIQuickAction) -> Void
    private let onDismiss: () -> Void

    public init(
        selectedText: String,
        chapterTitle: String,
        bookTitle: String,
        onAction: @escaping (ReaderAIQuickAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.selectedText = selectedText
        self.chapterTitle = chapterTitle
        self.bookTitle = bookTitle
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.lg) {
                selectedTextCard

                VStack(spacing: AppSpacing.md) {
                    Text("Quick Actions")
                        .font(AppTypography.headline)
                        .foregroundStyle(Morandi.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(ReaderAIQuickAction.allCases) { action in
                        Button {
                            onAction(action)
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: action.systemImage)
                                    .font(AppTypography.title3)
                                    .foregroundStyle(Morandi.accent)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                    Text(action.title)
                                        .font(AppTypography.headline)
                                        .foregroundStyle(Morandi.primaryText)

                                    Text(action.subtitle)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(Morandi.secondaryText)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(Morandi.secondaryText)
                            }
                            .padding(AppSpacing.md)
                            .background(Morandi.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(AppSpacing.lg)
            .background(Morandi.background)
            .navigationTitle("AI Actions")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var selectedTextCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if !chapterTitle.isEmpty {
                Text(chapterTitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
            }

            Text(selectedText)
                .font(AppTypography.body)
                .foregroundStyle(Morandi.primaryText)
                .lineLimit(6)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                .fill(Morandi.cardBackground)
        )
    }
}

// MARK: - Quick Action Model

public enum ReaderAIQuickAction: String, CaseIterable, Identifiable, Sendable {
    case explain
    case translate
    case summarize
    case defineVocabulary

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .explain: return "Explain"
        case .translate: return "Translate"
        case .summarize: return "Summarize"
        case .defineVocabulary: return "Define"
        }
    }

    public var subtitle: String {
        switch self {
        case .explain: return "Get a clear explanation of this passage"
        case .translate: return "Translate to your preferred language"
        case .summarize: return "Get a concise summary of the key points"
        case .defineVocabulary: return "Look up word definitions and usage"
        }
    }

    public var systemImage: String {
        switch self {
        case .explain: return "lightbulb"
        case .translate: return "globe"
        case .summarize: return "text.justify.leading"
        case .defineVocabulary: return "character.book.closed"
        }
    }

    public func prompt(selectedText: String, bookTitle: String, chapterTitle: String) -> String {
        let contextLine = chapterTitle.isEmpty
            ? "from \"\(bookTitle)\""
            : "from \"\(bookTitle)\", chapter \"\(chapterTitle)\""
        switch self {
        case .explain:
            return "Please explain the following passage \(contextLine):\n\n\"\(selectedText)\""
        case .translate:
            return "Please translate the following passage \(contextLine) into English (or the user's preferred language):\n\n\"\(selectedText)\""
        case .summarize:
            return "Please summarize the key points of this passage \(contextLine):\n\n\"\(selectedText)\""
        case .defineVocabulary:
            return "Please define and explain the vocabulary in this passage \(contextLine):\n\n\"\(selectedText)\""
        }
    }
}
