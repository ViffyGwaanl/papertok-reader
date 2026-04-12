import Foundation
import Testing
@testable import PTFeatures
import PTCore
import PTReader

@Suite("EPUBReaderPreferencesViewModel")
@MainActor
struct EPUBReaderPreferencesViewModelTests {
    @Test("load falls back to default per-book reading preferences when nothing is persisted")
    func loadFallsBackToDefaults() async throws {
        let database = try AppDatabase.makeInMemory()
        let defaults = makeDefaults()
        let viewModel = EPUBReaderPreferencesViewModel(
            bookId: 101,
            database: database,
            defaults: defaults
        )

        await viewModel.load()

        #expect(viewModel.readingPreferences.style == .default)
        #expect(viewModel.readingPreferences.theme == .defaultLight)
        #expect(viewModel.readingPreferences.pageTurnMode == .swipe)
        #expect(viewModel.readingPreferences.textAlignment == .justify)
        #expect(viewModel.readingPreferences.isScrollMode == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("save persists book-scoped style theme and behavior preferences")
    func savePersistsBookScopedPreferences() async throws {
        let database = try AppDatabase.makeInMemory()
        let defaults = makeDefaults()
        let bookID: Int64 = 202
        let viewModel = EPUBReaderPreferencesViewModel(
            bookId: bookID,
            database: database,
            defaults: defaults
        )

        await viewModel.load()
        viewModel.readingPreferences.style.fontSize = 1.95
        viewModel.readingPreferences.style.fontFamily = "Georgia"
        viewModel.readingPreferences.style.lineHeight = 1.7
        viewModel.readingPreferences.style.letterSpacing = 0.08
        viewModel.readingPreferences.style.wordSpacing = 0.14
        viewModel.readingPreferences.style.paragraphSpacing = 1.25
        viewModel.readingPreferences.style.sideMargin = 3.5
        viewModel.readingPreferences.style.topMargin = 72
        viewModel.readingPreferences.style.bottomMargin = 44
        viewModel.readingPreferences.theme = .defaultDark
        viewModel.readingPreferences.pageTurnMode = .scroll
        viewModel.readingPreferences.textAlignment = .center
        viewModel.readingPreferences.isScrollMode = true

        await viewModel.save()

        let persistedStyle = try #require(await BookStyleDAO(database: database).fetchById(bookID))
        let persistedTheme = try #require(await ReadThemeDAO(database: database).fetchById(bookID))
        #expect(persistedStyle.id == bookID)
        #expect(persistedStyle.fontSize == 1.95)
        #expect(persistedStyle.fontFamily == "Georgia")
        #expect(persistedStyle.lineHeight == 1.7)
        #expect(persistedStyle.letterSpacing == 0.08)
        #expect(persistedStyle.wordSpacing == 0.14)
        #expect(persistedStyle.paragraphSpacing == 1.25)
        #expect(persistedStyle.sideMargin == 3.5)
        #expect(persistedStyle.topMargin == 72)
        #expect(persistedStyle.bottomMargin == 44)
        #expect(persistedTheme.id == bookID)
        #expect(persistedTheme.backgroundColor == ReadTheme.defaultDark.backgroundColor)
        #expect(persistedTheme.textColor == ReadTheme.defaultDark.textColor)
        #expect(
            defaults.string(
                forKey: EPUBReaderPreferencesViewModel.StorageKeys.pageTurnMode(bookId: bookID)
            ) == PageTurnMode.scroll.rawValue
        )
        #expect(
            defaults.string(
                forKey: EPUBReaderPreferencesViewModel.StorageKeys.textAlignment(bookId: bookID)
            ) == TextAlignment.center.rawValue
        )

        let reloaded = EPUBReaderPreferencesViewModel(
            bookId: bookID,
            database: database,
            defaults: defaults
        )
        await reloaded.load()

        #expect(reloaded.readingPreferences.style == persistedStyle)
        #expect(reloaded.readingPreferences.theme == persistedTheme)
        #expect(reloaded.readingPreferences.pageTurnMode == .scroll)
        #expect(reloaded.readingPreferences.textAlignment == .center)
        #expect(reloaded.readingPreferences.isScrollMode)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "tests.epub-reader-preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
