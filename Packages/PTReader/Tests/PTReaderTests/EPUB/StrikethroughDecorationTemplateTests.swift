#if canImport(UIKit)
import Foundation
import Testing
@testable import PTReader
import PTCore
import ReadiumShared

@Suite("StrikethroughDecorationTemplate")
struct StrikethroughDecorationTemplateTests {
    @Test("Stylesheet defines the overlay class with a line-through rule")
    func stylesheetContainsOverlayRule() {
        let css = StrikethroughDecorationTemplate.stylesheet
        #expect(css.contains("pt-strikethrough-overlay"))
        #expect(css.contains("line-through") || css.contains("border-top"))
    }

    @Test("htmlTemplate builds without crashing")
    func htmlTemplateBuilds() {
        _ = StrikethroughDecorationTemplate.htmlTemplate()
    }

    @Test("renderElementHTML emits escaped tint style")
    func renderElementEscapesTint() {
        let href = AnyURL(path: "ch1.xhtml")!
        let locator = Locator(href: href, mediaType: .xhtml, title: "Chapter 1")
        let decoration = StrikethroughDecorationTemplate.decoration(
            id: "1",
            locator: locator,
            tintHex: "#F44336"
        )
        let html = StrikethroughDecorationTemplate.renderElementHTML(for: decoration)
        #expect(html.contains("pt-strikethrough-overlay"))
        #expect(html.contains("#F44336"))
        #expect(html.contains("<script>") == false)
    }

    @Test("renderElementHTML escapes a malicious id-like tint payload")
    func renderElementRejectsScript() {
        let href = AnyURL(path: "ch2.xhtml")!
        let locator = Locator(href: href, mediaType: .xhtml, title: "Chapter 2")
        // Feed a bogus tint string containing HTML metacharacters. The id is
        // never embedded in the HTML, but whatever lands in userInfo must be
        // escaped so `<script>` can never appear literally.
        let decoration = StrikethroughDecorationTemplate.decoration(
            id: "<script>alert(1)</script>",
            locator: locator,
            tintHex: "<script>alert(1)</script>"
        )
        let html = StrikethroughDecorationTemplate.renderElementHTML(for: decoration)
        #expect(html.contains("<script>") == false)
    }

    @Test("The five Morandi highlight colors normalize to five distinct tint hexes")
    func fiveColorsFiveHexes() {
        let hexes = HighlightColor.allCases.map { color in
            StrikethroughDecorationTemplate.normalizedTintHex(color.hex)
        }
        #expect(Set(hexes).count == HighlightColor.allCases.count)
        for hex in hexes {
            #expect(hex.hasPrefix("#"))
            #expect(hex.count == 7)
        }
    }

    @Test("normalizedTintHex strips an existing AARRGGBB alpha prefix")
    func normalizedTintHexStripsAlpha() {
        #expect(StrikethroughDecorationTemplate.normalizedTintHex("FFF44336") == "#F44336")
        #expect(StrikethroughDecorationTemplate.normalizedTintHex("#FFF44336") == "#F44336")
        #expect(StrikethroughDecorationTemplate.normalizedTintHex("F44336") == "#F44336")
        #expect(StrikethroughDecorationTemplate.normalizedTintHex("junk") == StrikethroughDecorationTemplate.defaultTintHex)
    }

    @Test("decoration factory populates tint userInfo and style id")
    func decorationFactoryPopulatesUserInfo() {
        let href = AnyURL(path: "ch3.xhtml")!
        let locator = Locator(href: href, mediaType: .xhtml, title: "Chapter 3")
        let decoration = StrikethroughDecorationTemplate.decoration(
            id: "abc",
            locator: locator,
            tintHex: HighlightColor.green.hex
        )
        #expect(decoration.style.id == StrikethroughDecorationTemplate.styleID)
        let tint = decoration.userInfo[StrikethroughDecorationTemplate.userInfoTintKey as AnyHashable] as? String
        #expect(tint == "#4CAF50")
    }
}
#endif
