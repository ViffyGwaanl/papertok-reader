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
    private let onActionWithScope: ((ReaderAIQuickAction, ReaderContextScope) -> Void)?
    private let onDismiss: () -> Void

    @AppStorage("reader.ai.last_scope") private var lastScopeRaw: String = ReaderContextScope.selection.rawValue
    @State private var scope: ReaderContextScope = .selection

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
        self.onActionWithScope = nil
        self.onDismiss = onDismiss
    }

    public init(
        selectedText: String,
        chapterTitle: String,
        bookTitle: String,
        onActionWithScope: @escaping (ReaderAIQuickAction, ReaderContextScope) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.selectedText = selectedText
        self.chapterTitle = chapterTitle
        self.bookTitle = bookTitle
        self.onAction = { _ in }
        self.onActionWithScope = onActionWithScope
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.lg) {
                selectedTextCard

                scopePicker

                VStack(spacing: AppSpacing.md) {
                    Text("reader.quick_actions")
                        .font(AppTypography.headline)
                        .foregroundStyle(Morandi.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(ReaderAIQuickAction.allCases) { action in
                        Button {
                            if let onActionWithScope {
                                onActionWithScope(action, scope)
                            } else {
                                onAction(action)
                            }
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
            .navigationTitle(String(localized: "reader.ai_actions"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close"), action: onDismiss)
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            if let stored = ReaderContextScope(rawValue: lastScopeRaw) {
                scope = stored
            } else {
                scope = selectedText.isEmpty ? .page : .selection
            }
        }
        .onChange(of: scope) { _, newValue in
            lastScopeRaw = newValue.rawValue
        }
    }

    private var scopePicker: some View {
        Picker(selection: $scope) {
            ForEach(ReaderContextScope.allCases, id: \.self) { option in
                Label(
                    localizedCatalogString(Self.scopeLabelKey(option)),
                    systemImage: Self.scopeSystemImage(option)
                )
                .tag(option)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private static func scopeLabelKey(_ scope: ReaderContextScope) -> String {
        switch scope {
        case .selection: return "reader.context.scope.selection"
        case .page: return "reader.context.scope.page"
        case .chapter: return "reader.context.scope.chapter"
        case .wholeBook: return "reader.context.scope.whole_book"
        }
    }

    private static func scopeSystemImage(_ scope: ReaderContextScope) -> String {
        switch scope {
        case .selection: return "text.cursor"
        case .page: return "doc.text"
        case .chapter: return "book.pages"
        case .wholeBook: return "books.vertical"
        }
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

    var titleKey: String {
        switch self {
        case .explain: return "reader.quick_action.explain.title"
        case .translate: return "reader.quick_action.translate.title"
        case .summarize: return "reader.quick_action.summarize.title"
        case .defineVocabulary: return "reader.quick_action.define_vocabulary.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .explain: return "reader.quick_action.explain.subtitle"
        case .translate: return "reader.quick_action.translate.subtitle"
        case .summarize: return "reader.quick_action.summarize.subtitle"
        case .defineVocabulary: return "reader.quick_action.define_vocabulary.subtitle"
        }
    }

    public var title: String {
        localizedCatalogString(titleKey)
    }

    public var subtitle: String {
        localizedCatalogString(subtitleKey)
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
        let hasChapter = !chapterTitle.isEmpty
        if hasChapter {
            return localizedCatalogFormat(
                promptKey(hasChapter: true),
                bookTitle,
                chapterTitle,
                selectedText
            )
        }

        return localizedCatalogFormat(
            promptKey(hasChapter: false),
            bookTitle,
            selectedText
        )
    }

    private func promptKey(hasChapter: Bool) -> String {
        switch (self, hasChapter) {
        case (.explain, true): return "reader.quick_action.explain.prompt.chapter"
        case (.explain, false): return "reader.quick_action.explain.prompt.book"
        case (.translate, true): return "reader.quick_action.translate.prompt.chapter"
        case (.translate, false): return "reader.quick_action.translate.prompt.book"
        case (.summarize, true): return "reader.quick_action.summarize.prompt.chapter"
        case (.summarize, false): return "reader.quick_action.summarize.prompt.book"
        case (.defineVocabulary, true): return "reader.quick_action.define_vocabulary.prompt.chapter"
        case (.defineVocabulary, false): return "reader.quick_action.define_vocabulary.prompt.book"
        }
    }

}

private func localizedCatalogString(_ key: String, locale: Locale = .autoupdatingCurrent) -> String {
    String(localized: String.LocalizationValue(key), bundle: localizedCatalogBundle(), locale: locale)
}

private func localizedCatalogFormat(_ key: String, locale: Locale = .autoupdatingCurrent, _ arguments: CVarArg...) -> String {
    String(format: localizedCatalogString(key, locale: locale), locale: locale, arguments: arguments)
}

private func localizedCatalogBundle() -> Bundle {
    let bundles = Bundle.allBundles + Bundle.allFrameworks

    if Bundle.main.bundleURL.pathExtension == "app" {
        return .main
    }
    if let appBundle = bundles.first(where: { $0.bundleIdentifier == "ai.papertok.paperreader" }) {
        return appBundle
    }
    let candidateDirectories = Set(bundles.map { $0.bundleURL.deletingLastPathComponent() })
    for directory in candidateDirectories {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { continue }

        for candidateURL in urls where candidateURL.pathExtension == "app" {
            if let appBundle = Bundle(url: candidateURL),
               appBundle.bundleIdentifier == "ai.papertok.paperreader" {
                return appBundle
            }
        }
    }
    return bundles.first(where: { $0.bundleURL.pathExtension == "app" }) ?? .main
}
