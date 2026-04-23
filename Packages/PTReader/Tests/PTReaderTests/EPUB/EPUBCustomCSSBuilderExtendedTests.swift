import Testing
import Foundation
@testable import PTReader
import PTCore

/// W6.3a — Extended CSS builder tests covering the new settings
/// (column count, writing mode, word/paragraph spacing, top/bottom margin).
@Suite("EPUBCustomCSSBuilderExtended")
struct EPUBCustomCSSBuilderExtendedTests {
    @Test("CSS includes column-count variable when single")
    func cssIncludesColumnCountVariableSingle() {
        var style = BookStyle.default
        style.maxColumnCount = .single
        let css = EPUBCustomCSSBuilder.buildCSS(style: style, theme: .defaultLight)
        #expect(css.contains("--readium-column-count"))
        #expect(css.contains("--readium-column-count: 1"))
    }

    @Test("CSS includes column-count variable when double")
    func cssIncludesColumnCountVariableDouble() {
        var style = BookStyle.default
        style.maxColumnCount = .double
        let css = EPUBCustomCSSBuilder.buildCSS(style: style, theme: .defaultLight)
        #expect(css.contains("--readium-column-count: 2"))
    }

    @Test("CSS includes column-count variable when auto")
    func cssIncludesColumnCountVariableAuto() {
        var style = BookStyle.default
        style.maxColumnCount = .auto
        let css = EPUBCustomCSSBuilder.buildCSS(style: style, theme: .defaultLight)
        #expect(css.contains("--readium-column-count: auto"))
    }

    @Test("CSS includes writing-mode variable for horizontal")
    func cssIncludesWritingModeVariableHorizontal() {
        var style = BookStyle.default
        style.writingMode = .horizontalTb
        let css = EPUBCustomCSSBuilder.buildCSS(style: style, theme: .defaultLight)
        #expect(css.contains("--readium-writing-mode"))
        #expect(css.contains("horizontal-tb"))
    }

    @Test("CSS includes writing-mode variable for vertical")
    func cssIncludesWritingModeVariableVertical() {
        var style = BookStyle.default
        style.writingMode = .verticalRl
        let css = EPUBCustomCSSBuilder.buildCSS(style: style, theme: .defaultLight)
        #expect(css.contains("vertical-rl"))
    }

    @Test("CSS includes word-spacing variable")
    func cssIncludesWordSpacingVariable() {
        var style = BookStyle.default
        style.wordSpacing = 0.5
        let css = EPUBCustomCSSBuilder.buildCSS(style: style, theme: .defaultLight)
        #expect(css.contains("--readium-word-spacing"))
        #expect(css.contains("0.50em"))
    }

    @Test("CSS includes paragraph-spacing variable")
    func cssIncludesParagraphSpacingVariable() {
        var style = BookStyle.default
        style.paragraphSpacing = 2.0
        let css = EPUBCustomCSSBuilder.buildCSS(style: style, theme: .defaultLight)
        #expect(css.contains("--readium-para-spacing"))
        #expect(css.contains("2em"))
    }

    @Test("CSS includes top/bottom margin variables")
    func cssIncludesTopBottomMarginVariables() {
        var style = BookStyle.default
        style.topMargin = 24
        style.bottomMargin = 18
        let css = EPUBCustomCSSBuilder.buildCSS(style: style, theme: .defaultLight)
        #expect(css.contains("--readium-top-margin"))
        #expect(css.contains("24px"))
        #expect(css.contains("--readium-bottom-margin"))
        #expect(css.contains("18px"))
    }
}
