import Foundation
import Testing
@testable import PTCore

@Suite("LocalizedSort")
struct LocalizedSortTests {
    @Test("uses pinyin ordering for Simplified Chinese locales")
    func usesPinyinOrderingForChinese() {
        let values = ["李白", "杜甫", "王维"]
        let sorted = values.sorted {
            LocalizedSort.compare($0, $1, locale: Locale(identifier: "zh-Hans")) == .orderedAscending
        }

        #expect(sorted == ["杜甫", "李白", "王维"])
    }

    @Test("uses locale-aware case-insensitive ordering for non-Chinese locales")
    func usesStandardOrderingForNonChinese() {
        let values = ["beta", "Alpha", "charlie"]
        let sorted = values.sorted {
            LocalizedSort.compare($0, $1, locale: Locale(identifier: "en")) == .orderedAscending
        }

        #expect(sorted == ["Alpha", "beta", "charlie"])
    }
}
