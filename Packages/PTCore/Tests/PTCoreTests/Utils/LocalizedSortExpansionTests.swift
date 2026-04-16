import Foundation
import Testing
@testable import PTCore

@Suite("LocalizedSort expansion")
struct LocalizedSortExpansionTests {
    @Test("conversation titles sort by pinyin for Chinese locale")
    func conversationTitlesSortByPinyinForChineseLocale() {
        // Pinyin: bai < hei < hong
        let titles = ["红", "白", "黑"]
        let sorted = titles.sorted {
            LocalizedSort.isAscending($0, $1, locale: Locale(identifier: "zh-Hans"))
        }
        #expect(sorted == ["白", "黑", "红"])
    }

    @Test("English titles sort normally")
    func englishTitlesSortNormally() {
        let titles = ["Charlie", "alpha", "Bravo"]
        let sorted = titles.sorted {
            LocalizedSort.isAscending($0, $1, locale: Locale(identifier: "en"))
        }
        #expect(sorted == ["alpha", "Bravo", "Charlie"])
    }

    @Test("mixed CJK and ASCII titles sort together for Chinese locale")
    func mixedCJKAndASCIISortForChineseLocale() {
        let titles = ["Python Guide", "白鹿原", "Alice"]
        let sorted = titles.sorted {
            LocalizedSort.isAscending($0, $1, locale: Locale(identifier: "zh-Hans"))
        }
        // "Alice" < "白鹿原" (bailuyuan) < "Python Guide"
        #expect(sorted == ["Alice", "白鹿原", "Python Guide"])
    }
}
