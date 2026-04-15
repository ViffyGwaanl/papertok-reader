import Foundation
import PTCore
import Testing
@testable import PaperTokReader

@Suite("ShareAndShortcutsSettings")
struct ShareAndShortcutsSettingsTests {
    @Test("defaults stay compatible with the Flutter share settings slice")
    func defaultsMatchFlutterCompatibleValues() throws {
        let suiteName = "ShareAndShortcutsSettingsDefaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = ShareAndShortcutsSettingsStore(defaults: defaults).load()

        #expect(settings.defaultRoute == .auto)
        #expect(settings.ttlDays == 7)
        #expect(settings.cleanupAfterUse)
    }

    @Test("saving the preferred route keeps native and Flutter keys in sync")
    func routeSaveSynchronizesCompatibilityKeys() throws {
        let suiteName = "ShareAndShortcutsSettingsRoute.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = ShareAndShortcutsSettingsStore(defaults: defaults)
        store.save(
            ShareAndShortcutsSettings(
                defaultRoute: .ask,
                ttlDays: 30,
                cleanupAfterUse: false
            )
        )

        #expect(defaults.string(forKey: AppConfig.Keys.shareDefaultRoute) == ShareDefaultRoute.ask.rawValue)
        #expect(defaults.string(forKey: ShareAndShortcutsSettingsStore.legacyShareModeKey) == ShareDefaultRoute.ask.rawValue)
        #expect(ShareDefaultRoute.current(defaults: defaults) == .ask)
    }

    @Test("share settings round-trip preserves TTL and cleanup behavior")
    func settingsRoundTripPreservesTTLAndCleanupBehavior() throws {
        let suiteName = "ShareAndShortcutsSettingsRoundTrip.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = ShareAndShortcutsSettingsStore(defaults: defaults)
        store.save(
            ShareAndShortcutsSettings(
                defaultRoute: .bookshelf,
                ttlDays: 30,
                cleanupAfterUse: false
            )
        )

        let restored = store.load()

        #expect(restored.defaultRoute == .bookshelf)
        #expect(restored.ttlDays == 30)
        #expect(restored.cleanupAfterUse == false)
        #expect(defaults.integer(forKey: ShareAndShortcutsSettingsStore.legacyTTLDaysKey) == 30)
        #expect(defaults.bool(forKey: ShareAndShortcutsSettingsStore.legacyCleanupAfterUseKey) == false)
    }

    @Test("share route titles resolve localized user-facing copy")
    func shareRouteTitlesResolveLocalizedCopy() {
        #expect(ShareDefaultRoute.auto.localizedTitle != "share.settings.route.auto")
        #expect(ShareDefaultRoute.ask.localizedTitle != "share.settings.route.ask")
        #expect(SharedInboxRoute.ask.localizedTitle != "share.settings.route.ask")
    }
}
