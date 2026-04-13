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
            #expect(!prompt.isEmpty)
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
        #expect(!prompt.contains("\"\""))
    }

    @Test("all quick actions have titles and icons")
    func allQuickActionsHaveTitlesAndIcons() {
        for action in ReaderAIQuickAction.allCases {
            #expect(!action.title.isEmpty)
            #expect(!action.subtitle.isEmpty)
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
