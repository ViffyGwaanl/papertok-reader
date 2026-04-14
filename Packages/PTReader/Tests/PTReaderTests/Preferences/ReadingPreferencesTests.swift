import Testing
import Foundation
@testable import PTReader

@Suite("ReadingPreferences")
struct ReadingPreferencesTests {
    @Test("Initializes with default style and theme")
    func defaultInit() {
        let prefs = ReadingPreferences()
        #expect(prefs.style.fontSize == 1.4)
        #expect(
            prefs.style.fontFamily
                == BookStyle.preferredDefaultFontFamily(locale: .autoupdatingCurrent)
        )
        #expect(prefs.theme.backgroundColor == "FFFBFBF3")
    }

    @Test("Initializes from existing BookStyle and ReadTheme")
    func customInit() {
        var style = BookStyle.default
        style.fontSize = 2.0
        let theme = ReadTheme.defaultDark
        let prefs = ReadingPreferences(style: style, theme: theme)
        #expect(prefs.style.fontSize == 2.0)
        #expect(prefs.theme.backgroundColor == "FF1A1A2E")
    }

    @Test("Page turn mode has all expected cases")
    func pageTurnModes() {
        #expect(PageTurnMode.allCases.count == 3)
        #expect(PageTurnMode(rawValue: "swipe") == .swipe)
        #expect(PageTurnMode(rawValue: "tap") == .tap)
        #expect(PageTurnMode(rawValue: "scroll") == .scroll)
    }

    @Test("Text alignment has all expected cases")
    func textAlignments() {
        #expect(TextAlignment.allCases.count == 4)
        #expect(TextAlignment(rawValue: "left") == .left)
        #expect(TextAlignment(rawValue: "justify") == .justify)
    }
}
