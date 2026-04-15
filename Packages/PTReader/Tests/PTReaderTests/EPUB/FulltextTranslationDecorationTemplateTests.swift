#if canImport(ReadiumNavigator)
import XCTest
@testable import PTReader
import ReadiumShared

final class FulltextTranslationDecorationTemplateTests: XCTestCase {
    func testHTMLEscapeCoversSpecialCharacters() {
        let escaped = FulltextTranslationDecorationTemplate.htmlEscape("a & b < c > d \" e ' f")
        XCTAssertEqual(escaped, "a &amp; b &lt; c &gt; d &quot; e &#39; f")
    }

    func testStylesheetContainsRequiredSelectorsAndRules() {
        let css = FulltextTranslationDecorationTemplate.stylesheet
        XCTAssertTrue(css.contains(".pt-translation-overlay"))
        XCTAssertTrue(css.contains("font-size"))
        XCTAssertTrue(css.contains("color"))
        XCTAssertTrue(css.contains("pointer-events"))
    }

    func testHTMLTemplateElementEscapesTranslatedText() {
        _ = FulltextTranslationDecorationTemplate.htmlTemplate()
        let locator = Locator(
            href: AnyURL(string: "chapter.xhtml")!,
            mediaType: .xhtml
        )
        let decoration = FulltextTranslationDecorationTemplate.decoration(
            id: "p1",
            locator: locator,
            translatedText: "<script>alert(1)</script>"
        )
        let html = FulltextTranslationDecorationTemplate.renderElementHTML(for: decoration)
        XCTAssertTrue(html.contains("<div class=\"pt-translation-overlay\">"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
    }

    func testDecorationCarriesTranslationInUserInfo() {
        let locator = Locator(
            href: AnyURL(string: "chapter.xhtml")!,
            mediaType: .xhtml
        )
        let decoration = FulltextTranslationDecorationTemplate.decoration(
            id: "p42",
            locator: locator,
            translatedText: "你好"
        )
        XCTAssertEqual(decoration.id, "p42")
        XCTAssertEqual(decoration.style.id, FulltextTranslationDecorationTemplate.styleID)
        XCTAssertEqual(decoration.userInfo["translation" as AnyHashable] as? String, "你好")
        XCTAssertEqual(decoration.userInfo["paragraphId" as AnyHashable] as? String, "p42")
    }
}
#endif
