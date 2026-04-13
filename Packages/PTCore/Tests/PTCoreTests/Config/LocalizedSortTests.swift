import Foundation
import Testing
@testable import PTCore

@Suite("LocalizedSort")
struct LocalizedSortTests {
    @Test("Chinese locales sort Han characters by pinyin")
    func chineseLocalesUsePinyinOrdering() {
        let values = ["上海", "北京", "广州"]

        let sorted = values.sorted { lhs, rhs in
            LocalizedSort.areInAscendingOrder(lhs, rhs, locale: Locale(identifier: "zh-Hans"))
        }

        #expect(sorted == ["北京", "广州", "上海"])
    }

    @Test("Non-Chinese locales keep localized comparison behavior")
    func nonChineseLocalesUseLocalizedComparison() {
        let values = ["banana", "Apple", "cherry"]

        let sorted = values.sorted { lhs, rhs in
            LocalizedSort.areInAscendingOrder(lhs, rhs, locale: Locale(identifier: "en-US"))
        }

        #expect(sorted == ["Apple", "banana", "cherry"])
    }

    @Test("Chinese sort keys fold tone marks and casing")
    func chineseSortKeysAreStable() {
        let key = LocalizedSort.sortKey(for: "重庆", locale: Locale(identifier: "zh-Hans"))

        #expect(key.contains("chong"))
        #expect(key == key.lowercased())
    }
}
