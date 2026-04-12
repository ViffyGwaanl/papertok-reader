import Foundation
import Testing
@testable import PTFeatures

@Suite("ReaderAIPanelPreferencesStore")
struct ReaderAIPanelPreferencesStoreTests {
    @Test("persists panel side and width per book")
    func persistsPanelSideAndWidthPerBook() {
        let defaults = makeDefaults()
        let store = ReaderAIPanelPreferencesStore(defaults: defaults)

        store.save(.init(side: .leading, width: 412), for: 7)
        store.save(.init(side: .trailing, width: 356), for: 8)

        #expect(store.load(for: 7) == .init(side: .leading, width: 412))
        #expect(store.load(for: 8) == .init(side: .trailing, width: 356))
    }

    @Test("invalid stored width falls back to the default width")
    func invalidStoredWidthFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set(-12, forKey: "reader.ai_panel.book.11.width")
        defaults.set("leading", forKey: "reader.ai_panel.book.11.side")

        let store = ReaderAIPanelPreferencesStore(defaults: defaults)

        #expect(
            store.load(for: 11) == .init(
                side: .leading,
                width: ReaderAIPanelMetrics.defaultWidth
            )
        )
    }

    @Test("clamps dock width into the allowed range for the available space")
    func clampsWidthIntoAllowedRange() {
        #expect(ReaderAIPanelMetrics.clampedWidth(120, availableWidth: 500) == 260)
        #expect(ReaderAIPanelMetrics.clampedWidth(800, availableWidth: 1200) == 540)
        #expect(ReaderAIPanelMetrics.clampedWidth(360, availableWidth: 900) == 360)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ReaderAIPanelPreferencesStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
