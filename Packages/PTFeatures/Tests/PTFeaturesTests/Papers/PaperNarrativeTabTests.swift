import Foundation
import Testing
@testable import PTFeatures

@Suite("PaperNarrativeTab")
struct PaperNarrativeTabTests {

    @Test("Default tab is explanation")
    func defaultTabIsExplanation() {
        #expect(PaperNarrativeTab.defaultTab == .explanation)
    }

    @Test("All cases are surfaced in order explanation -> dialogue")
    func allCasesOrdered() {
        #expect(PaperNarrativeTab.allCases == [.explanation, .dialogue])
    }

    @Test("Title keys map each case to its localization key")
    func titleKeysAreStable() {
        #expect(PaperNarrativeTab.explanation.titleKey == "papers.detail.tab.explanation")
        #expect(PaperNarrativeTab.dialogue.titleKey == "papers.detail.tab.dialogue")
    }

    @Test("Raw values round-trip through String")
    func rawValueRoundTrips() {
        for tab in PaperNarrativeTab.allCases {
            let roundTripped = PaperNarrativeTab(rawValue: tab.rawValue)
            #expect(roundTripped == tab)
        }
    }

    @Test("Markdown renderer returns parsed AttributedString for simple bold")
    func markdownRendersInlineBold() {
        let rendered = PaperMarkdown.render("Hello **world**")
        let plain = String(rendered.characters)
        #expect(plain.contains("Hello"))
        #expect(plain.contains("world"))
    }

    @Test("Markdown renderer returns empty AttributedString for empty input")
    func markdownHandlesEmpty() {
        let rendered = PaperMarkdown.render("")
        #expect(String(rendered.characters).isEmpty)
    }
}
