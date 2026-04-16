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
        var routeSettings = ShareAndShortcutsSettings.default
        routeSettings.defaultRoute = .ask
        routeSettings.ttlDays = 30
        routeSettings.cleanupAfterUse = false
        store.save(routeSettings)

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
        var rtSettings = ShareAndShortcutsSettings.default
        rtSettings.defaultRoute = .bookshelf
        rtSettings.ttlDays = 30
        rtSettings.cleanupAfterUse = false
        store.save(rtSettings)

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

    @Test("ask-before-routing persists and round-trips correctly")
    func askBeforeRoutingRoundTrip() throws {
        let suiteName = "ShareAndShortcutsAskBeforeRouting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = ShareAndShortcutsSettingsStore(defaults: defaults)
        var settings = store.load()
        #expect(settings.askBeforeRouting == false)

        settings.askBeforeRouting = true
        store.save(settings)
        let restored = store.load()
        #expect(restored.askBeforeRouting == true)
    }

    @Test("session target persists and round-trips correctly")
    func sessionTargetRoundTrip() throws {
        let suiteName = "ShareAndShortcutsSessionTarget.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = ShareAndShortcutsSettingsStore(defaults: defaults)
        var settings = store.load()
        #expect(settings.sessionTarget == .automatic)

        settings.sessionTarget = .newConversation
        store.save(settings)
        let restored = store.load()
        #expect(restored.sessionTarget == .newConversation)
    }

    @Test("attachment limits persist and round-trip correctly")
    func attachmentLimitsRoundTrip() throws {
        let suiteName = "ShareAndShortcutsAttachLimits.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = ShareAndShortcutsSettingsStore(defaults: defaults)
        var settings = store.load()
        #expect(settings.maxAttachmentSizeMB == 10)
        #expect(settings.maxAttachmentCount == 5)

        settings.maxAttachmentSizeMB = 25
        settings.maxAttachmentCount = 3
        store.save(settings)
        let restored = store.load()
        #expect(restored.maxAttachmentSizeMB == 25)
        #expect(restored.maxAttachmentCount == 3)
    }

    @Test("defaults for new fields are backward compatible when no stored data exists")
    func newFieldDefaultsAreBackwardCompatible() throws {
        let suiteName = "ShareAndShortcutsBackcompat.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        // Simulate legacy storage: only old keys
        defaults.set(ShareDefaultRoute.bookshelf.rawValue, forKey: AppConfig.Keys.shareDefaultRoute)
        defaults.set(14, forKey: ShareAndShortcutsSettingsStore.legacyTTLDaysKey)
        defaults.set(false, forKey: ShareAndShortcutsSettingsStore.legacyCleanupAfterUseKey)

        let store = ShareAndShortcutsSettingsStore(defaults: defaults)
        let settings = store.load()

        #expect(settings.defaultRoute == .bookshelf)
        #expect(settings.ttlDays == 14)
        #expect(settings.cleanupAfterUse == false)
        #expect(settings.askBeforeRouting == false)
        #expect(settings.sessionTarget == .automatic)
        #expect(settings.maxAttachmentSizeMB == 10)
        #expect(settings.maxAttachmentCount == 5)
    }
}
