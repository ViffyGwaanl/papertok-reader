import Foundation
import Testing
@testable import PaperTokReader

@Suite("Fulltext translation per-book preference")
struct FulltextTranslationPreferenceTests {
    @Test("distinct book ids map to distinct preference keys")
    func distinctKeysPerBook() {
        let keyA = EPUBBookshelfReaderView.fulltextTranslationPreferenceKey(for: 101)
        let keyB = EPUBBookshelfReaderView.fulltextTranslationPreferenceKey(for: 202)
        #expect(keyA != keyB)
        #expect(keyA == "reader.fulltext_translation.enabled.101")
        #expect(keyB == "reader.fulltext_translation.enabled.202")
    }

    @Test("round-trips in an isolated UserDefaults suite")
    func roundTripInIsolatedSuite() throws {
        let suiteName = "FulltextTranslationPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = EPUBBookshelfReaderView.fulltextTranslationPreferenceKey(for: 777)
        #expect(defaults.bool(forKey: key) == false)

        defaults.set(true, forKey: key)
        #expect(defaults.bool(forKey: key) == true)

        defaults.set(false, forKey: key)
        #expect(defaults.bool(forKey: key) == false)
    }

    @Test("keys for neighbouring book ids do not collide")
    func neighbouringBookIdsNoCollision() throws {
        let suiteName = "FulltextTranslationPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let k1 = EPUBBookshelfReaderView.fulltextTranslationPreferenceKey(for: 1)
        let k2 = EPUBBookshelfReaderView.fulltextTranslationPreferenceKey(for: 2)
        defaults.set(true, forKey: k1)
        #expect(defaults.bool(forKey: k1) == true)
        #expect(defaults.bool(forKey: k2) == false)
    }
}
