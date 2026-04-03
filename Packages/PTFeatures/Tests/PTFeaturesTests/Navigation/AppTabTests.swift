import Testing
import Foundation
@testable import PTFeatures

@Suite("AppTab")
struct AppTabTests {
    @Test("Has 6 tabs")
    func tabCount() {
        #expect(AppTab.allCases.count == 6)
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
        #expect(AppTab.defaultOrder.count == 6)
        #expect(Set(AppTab.defaultOrder) == Set(AppTab.allCases))
    }
}
