import Testing
import Foundation
import PTCore
@testable import PTFeatures

@Suite("AppTab")
struct AppTabTests {
    @Test("Has 7 tabs including memory")
    func tabCount() {
        #expect(AppTab.allCases.count == 7)
        #expect(AppTab.allCases.contains(.memory))
    }

    @Test("Each tab has title and icon")
    func titlesAndIcons() {
        for tab in AppTab.allCases {
            #expect(!tab.title.isEmpty)
            #expect(!tab.icon.isEmpty)
        }
    }

    @Test("Default order matches all cases")
    func defaultOrder() {
        #expect(AppTab.defaultOrder.count == 7)
        #expect(Set(AppTab.defaultOrder) == Set(AppTab.allCases))
    }

    @Test("currentOrder appends newly introduced tabs to older saved layouts")
    func currentOrderAppendsNewTabs() {
        let defaults = UserDefaults(suiteName: AppConfig.suiteName) ?? .standard
        let oldOrder = ["papers", "bookshelf", "notes", "statistics", "ai", "settings"]
        defaults.set(oldOrder, forKey: "home_nav_tab_order")
        defaults.set(oldOrder, forKey: "home_nav_enabled_tabs")
        defer {
            defaults.removeObject(forKey: "home_nav_tab_order")
            defaults.removeObject(forKey: "home_nav_enabled_tabs")
        }

        let order = AppTab.currentOrder()
        #expect(order.contains(.memory))
        #expect(order.last == .settings)
    }
}
