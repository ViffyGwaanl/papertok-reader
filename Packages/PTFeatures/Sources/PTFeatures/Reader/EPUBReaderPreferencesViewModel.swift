import Foundation
import Observation
import PTCore
import PTReader

@MainActor @Observable
public final class EPUBReaderPreferencesViewModel {
    public enum StorageKeys {
        public static func pageTurnMode(bookId: Int64) -> String {
            "reader.preferences.book.\(bookId).pageTurnMode"
        }

        public static func textAlignment(bookId: Int64) -> String {
            "reader.preferences.book.\(bookId).textAlignment"
        }
    }

    public let bookId: Int64
    public let readingPreferences: ReadingPreferences
    public private(set) var errorMessage: String?

    private let styleDAO: BookStyleDAO
    private let themeDAO: ReadThemeDAO
    private let defaults: UserDefaults

    public init(
        bookId: Int64,
        database: AppDatabase,
        defaults: UserDefaults = AppConfig.groupDefaults
    ) {
        self.bookId = bookId
        self.readingPreferences = ReadingPreferences()
        self.styleDAO = BookStyleDAO(database: database)
        self.themeDAO = ReadThemeDAO(database: database)
        self.defaults = defaults
    }

    public func load() async {
        do {
            apply(
                style: try await styleDAO.fetchById(bookId) ?? .default,
                theme: try await themeDAO.fetchById(bookId) ?? .defaultLight,
                pageTurnMode: PageTurnMode(
                    rawValue: defaults.string(forKey: StorageKeys.pageTurnMode(bookId: bookId)) ?? ""
                ) ?? .swipe,
                textAlignment: TextAlignment(
                    rawValue: defaults.string(forKey: StorageKeys.textAlignment(bookId: bookId)) ?? ""
                ) ?? .justify
            )
            errorMessage = nil
        } catch {
            apply(
                style: .default,
                theme: .defaultLight,
                pageTurnMode: .swipe,
                textAlignment: .justify
            )
            errorMessage = error.localizedDescription
        }
    }

    public func save() async {
        do {
            var style = readingPreferences.style
            style.id = bookId
            var theme = readingPreferences.theme
            theme.id = bookId

            readingPreferences.style = try await styleDAO.save(style)
            readingPreferences.theme = try await themeDAO.save(theme)
            defaults.set(readingPreferences.pageTurnMode.rawValue, forKey: StorageKeys.pageTurnMode(bookId: bookId))
            defaults.set(readingPreferences.textAlignment.rawValue, forKey: StorageKeys.textAlignment(bookId: bookId))
            readingPreferences.isScrollMode = readingPreferences.pageTurnMode == .scroll
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func resetToDefaults() async {
        apply(
            style: .default,
            theme: .defaultLight,
            pageTurnMode: .swipe,
            textAlignment: .justify
        )
        await save()
    }

    public func clearError() {
        errorMessage = nil
    }

    private func apply(
        style: BookStyle,
        theme: ReadTheme,
        pageTurnMode: PageTurnMode,
        textAlignment: TextAlignment
    ) {
        readingPreferences.style = style
        readingPreferences.theme = theme
        readingPreferences.pageTurnMode = pageTurnMode
        readingPreferences.textAlignment = textAlignment
        readingPreferences.isScrollMode = pageTurnMode == .scroll
    }
}
