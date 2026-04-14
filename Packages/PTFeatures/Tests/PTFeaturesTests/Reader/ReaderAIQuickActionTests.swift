import Foundation
import Testing
@testable import PTFeatures

@Suite("ReaderAIQuickAction")
struct ReaderAIQuickActionTests {
    @Test("all cases produce non-empty prompts with context")
    func allCasesProducePrompts() {
        let selectedText = "The mitochondria is the powerhouse of the cell."
        let bookTitle = "Biology 101"
        let chapterTitle = "Cell Structure"

        for action in ReaderAIQuickAction.allCases {
            let prompt = action.prompt(selectedText: selectedText, bookTitle: bookTitle, chapterTitle: chapterTitle)
            #expect(prompt.contains(selectedText))
            #expect(prompt.contains(bookTitle))
            #expect(prompt.contains(chapterTitle))
            #expect(
                prompt == localizedCatalogFormat(
                    promptKey(for: action, hasChapter: true),
                    bookTitle,
                    chapterTitle,
                    selectedText
                )
            )
        }
    }

    @Test("prompt omits chapter when empty")
    func promptOmitsChapterWhenEmpty() {
        let prompt = ReaderAIQuickAction.explain.prompt(
            selectedText: "Some text",
            bookTitle: "My Book",
            chapterTitle: ""
        )
        #expect(prompt.contains("My Book"))
        #expect(prompt.contains("Some text"))
        #expect(
            prompt == localizedCatalogFormat(
                "reader.quick_action.explain.prompt.book",
                "My Book",
                "Some text"
            )
        )
    }

    @Test("all quick actions have titles and icons")
    func allQuickActionsHaveTitlesAndIcons() {
        for action in ReaderAIQuickAction.allCases {
            #expect(action.title != action.titleKey)
            #expect(action.subtitle != action.subtitleKey)
            #expect(action.title == localizedCatalogString(action.titleKey))
            #expect(action.subtitle == localizedCatalogString(action.subtitleKey))
            #expect(!action.systemImage.isEmpty)
        }
    }

    @Test("all quick actions expose localization keys")
    func quickActionLocalizationKeys() {
        #expect(ReaderAIQuickAction.explain.titleKey == "reader.quick_action.explain.title")
        #expect(ReaderAIQuickAction.explain.subtitleKey == "reader.quick_action.explain.subtitle")
        #expect(ReaderAIQuickAction.translate.titleKey == "reader.quick_action.translate.title")
        #expect(ReaderAIQuickAction.translate.subtitleKey == "reader.quick_action.translate.subtitle")
        #expect(ReaderAIQuickAction.summarize.titleKey == "reader.quick_action.summarize.title")
        #expect(ReaderAIQuickAction.summarize.subtitleKey == "reader.quick_action.summarize.subtitle")
        #expect(ReaderAIQuickAction.defineVocabulary.titleKey == "reader.quick_action.define_vocabulary.title")
        #expect(ReaderAIQuickAction.defineVocabulary.subtitleKey == "reader.quick_action.define_vocabulary.subtitle")
    }
}

private func promptKey(for action: ReaderAIQuickAction, hasChapter: Bool) -> String {
    switch (action, hasChapter) {
    case (.explain, true):
        "reader.quick_action.explain.prompt.chapter"
    case (.explain, false):
        "reader.quick_action.explain.prompt.book"
    case (.translate, true):
        "reader.quick_action.translate.prompt.chapter"
    case (.translate, false):
        "reader.quick_action.translate.prompt.book"
    case (.summarize, true):
        "reader.quick_action.summarize.prompt.chapter"
    case (.summarize, false):
        "reader.quick_action.summarize.prompt.book"
    case (.defineVocabulary, true):
        "reader.quick_action.define_vocabulary.prompt.chapter"
    case (.defineVocabulary, false):
        "reader.quick_action.define_vocabulary.prompt.book"
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
