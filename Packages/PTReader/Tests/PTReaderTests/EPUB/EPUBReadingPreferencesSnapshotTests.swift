import Testing
@testable import PTReader
import PTCore
import ReadiumNavigator

@Suite("EPUBReadingPreferencesSnapshot")
struct EPUBReadingPreferencesSnapshotTests {
    @Test("maps reading preferences into Readium navigator preferences and content insets")
    func mapsReadingPreferencesIntoReadiumPreferences() {
        var style = BookStyle.default
        style.id = 12
        style.fontSize = 1.9
        style.fontFamily = "Georgia"
        style.lineHeight = 1.6
        style.letterSpacing = 0.8
        style.wordSpacing = 0.12
        style.paragraphSpacing = 1.6
        style.sideMargin = 3.0
        style.topMargin = 84
        style.bottomMargin = 52
        let theme = ReadTheme.defaultDark
        let readingPreferences = ReadingPreferences(
            style: style,
            theme: theme,
            pageTurnMode: .scroll,
            textAlignment: .center,
            isScrollMode: true
        )

        let snapshot = EPUBReadingPreferencesSnapshot(readingPreferences: readingPreferences)

        #expect(snapshot.preferences.fontSize == 1.9)
        #expect(snapshot.preferences.fontFamily == FontFamily(rawValue: "Georgia"))
        #expect(snapshot.preferences.lineHeight == 1.6)
        #expect(snapshot.preferences.letterSpacing == 0.1)
        #expect(snapshot.preferences.wordSpacing == 0.12)
        #expect(snapshot.preferences.paragraphSpacing == 0.8)
        #expect(snapshot.preferences.pageMargins == 0.5)
        #expect(snapshot.preferences.scroll == true)
        #expect(snapshot.preferences.textAlign == ReadiumNavigator.TextAlignment.start)
        #expect(snapshot.preferences.theme == ReadiumNavigator.Theme.dark)
        #expect(snapshot.preferences.backgroundColor == Color(hex: theme.backgroundColor))
        #expect(snapshot.preferences.textColor == Color(hex: theme.textColor))
        #expect(snapshot.contentInsets.top == 84)
        #expect(snapshot.contentInsets.bottom == 52)
    }

    @Test("non-scroll page turn modes keep the navigator paginated")
    func nonScrollModesStayPaginated() {
        let readingPreferences = ReadingPreferences(
            style: .default,
            theme: .defaultLight,
            pageTurnMode: .tap,
            textAlignment: .justify,
            isScrollMode: false
        )

        let snapshot = EPUBReadingPreferencesSnapshot(readingPreferences: readingPreferences)

        #expect(snapshot.preferences.scroll == false)
        #expect(snapshot.preferences.textAlign == ReadiumNavigator.TextAlignment.justify)
        #expect(snapshot.preferences.theme == ReadiumNavigator.Theme.light)
    }
}
