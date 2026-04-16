import Testing
import Foundation
import PTCore
@testable import PTFeatures

@Suite("AppTab order")
struct AppTabOrderTests {
    @Test("Default order is five tabs")
    func defaultOrderIsFiveTabs() {
        #expect(AppTab.defaultOrder.count == 5)
    }

    @Test("Default order includes AI within first five")
    func defaultOrderIncludesAI() {
        #expect(AppTab.defaultOrder.contains(.ai))
        let aiIndex = AppTab.defaultOrder.firstIndex(of: .ai) ?? -1
        #expect(aiIndex >= 0)
        #expect(aiIndex < 5)
    }

    @Test("Default order fifth entry is settings")
    func defaultOrderFifthIsSettings() {
        #expect(AppTab.defaultOrder.last == .settings)
        #expect(AppTab.defaultOrder.count == 5)
        #expect(AppTab.defaultOrder[4] == .settings)
    }

    @Test("AllInstallableOrder has all seven tabs")
    func allInstallableOrderHasAllSeven() {
        #expect(AppTab.allInstallableOrder.count == 7)
        #expect(Set(AppTab.allInstallableOrder) == Set(AppTab.allCases))
    }

    @Test("AllInstallableOrder contains all default members")
    func allInstallableOrderContainsDefault() {
        for tab in AppTab.defaultOrder {
            #expect(AppTab.allInstallableOrder.contains(tab))
        }
    }

    @Test("Default order explicit shape")
    func defaultOrderExplicit() {
        #expect(AppTab.defaultOrder == [.papers, .bookshelf, .ai, .notes, .settings])
    }
}
