import Testing
import Foundation
@testable import PTFeatures
import PTAIServices

@Suite("CitationsRendering")
struct CitationsRenderingTests {

    // MARK: - CitationsFooterView

    @Test("footer renders nothing when citations empty")
    func footerRendersNothingWhenEmpty() {
        #expect(CitationsFooterView.shouldRender([]) == false)
    }

    @Test("footer renders one row per citation")
    func footerRendersOneRowPerCitation() {
        let citations = [
            MessageCitation(index: 1, title: "A"),
            MessageCitation(index: 2, title: "B"),
            MessageCitation(index: 3, title: "C"),
        ]
        #expect(CitationsFooterView.shouldRender(citations) == true)
        #expect(CitationsFooterView.rowCount(for: citations) == 3)
    }

    @Test("footer uses untitled fallback for empty title")
    func footerUsesUntitledFallbackForEmptyTitle() {
        let citation = MessageCitation(index: 1, title: "")
        let display = CitationsFooterView.displayTitle(for: citation)
        #expect(display == String(localized: "chat.message.citations.untitled"))
    }

    @Test("footer preserves non-empty title")
    func footerPreservesNonEmptyTitle() {
        let citation = MessageCitation(index: 1, title: "Attention Is All You Need")
        #expect(CitationsFooterView.displayTitle(for: citation) == "Attention Is All You Need")
    }

    // MARK: - CitationMarkdownRenderer

    @Test("parser recognizes single citation marker")
    func parserRecognizesCitationMarker() {
        let markers = CitationMarkdownRenderer.markers(in: "This is a fact [1].")
        #expect(markers.count == 1)
        #expect(markers.first?.index == 1)
    }

    @Test("parser handles multiple markers")
    func parserHandlesMultipleMarkers() {
        let markers = CitationMarkdownRenderer.markers(in: "Fact [1] and [2] and [10].")
        #expect(markers.map(\.index) == [1, 2, 10])
    }

    @Test("parser ignores non-numeric brackets")
    func parserIgnoresNonNumericBrackets() {
        let markers = CitationMarkdownRenderer.markers(in: "[Note] and [abc] and [1a]")
        #expect(markers.isEmpty)
    }

    @Test("renderer applies superscript attribute to marker range")
    func rendererAppliesSuperscriptAttribute() {
        let attributed = CitationMarkdownRenderer.render("See [1] now.")
        // Find the range of "[1]" and confirm baselineOffset attribute is present.
        let str = String(attributed.characters)
        #expect(str.contains("[1]"))
        var found = false
        for run in attributed.runs {
            if run.baselineOffset != nil && run.baselineOffset! > 0 {
                found = true
                break
            }
        }
        #expect(found)
    }
}
