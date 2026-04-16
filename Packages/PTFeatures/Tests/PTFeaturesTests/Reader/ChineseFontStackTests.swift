import Foundation
import Testing
@testable import PTCore

@Suite("Chinese font stack")
struct ChineseFontStackTests {
    @Test("font list starts with PingFang for Simplified Chinese")
    func fontListStartsWithPingFangForSimplifiedChinese() {
        let fonts = BookStyle.preferredFontFamilies(locale: Locale(identifier: "zh-Hans"))
        #expect(fonts.first?.contains("PingFang") == true || fonts.first?.contains("Songti") == true,
                Comment(rawValue: "First font should be CJK-optimized, got: \(fonts.first ?? "nil")"))
        // Verify CJK fonts appear before generic Western fonts
        let pingFangIndex = fonts.firstIndex(where: { $0.contains("PingFang") })
        let arialIndex = fonts.firstIndex(of: "Arial")
        if let pf = pingFangIndex, let ar = arialIndex {
            #expect(pf < ar, Comment(rawValue: "PingFang should appear before Arial"))
        }
        // Verify STSong is in the list for zh-Hans
        #expect(fonts.contains("STSong"), Comment(rawValue: "STSong should be in zh-Hans font list"))
        // Verify Heiti SC is in the list for zh-Hans
        #expect(fonts.contains("Heiti SC"), Comment(rawValue: "Heiti SC should be in zh-Hans font list"))
    }

    @Test("font list starts with traditional CJK fonts for Traditional Chinese")
    func fontListStartsWithCJKForTraditionalChinese() {
        let fonts = BookStyle.preferredFontFamilies(locale: Locale(identifier: "zh-Hant"))
        let pingFangIndex = fonts.firstIndex(where: { $0.contains("PingFang") })
        let arialIndex = fonts.firstIndex(of: "Arial")
        if let pf = pingFangIndex, let ar = arialIndex {
            #expect(pf < ar, Comment(rawValue: "PingFang should appear before Arial for zh-Hant"))
        }
        #expect(fonts.contains("Heiti TC"), Comment(rawValue: "Heiti TC should be in zh-Hant font list"))
    }

    @Test("font list unchanged for English locale")
    func fontListUnchangedForEnglishLocale() {
        let fonts = BookStyle.preferredFontFamilies(locale: Locale(identifier: "en"))
        // PingFang should NOT be the first font for English
        #expect(fonts.first != "PingFang SC" && fonts.first != "PingFang TC",
                Comment(rawValue: "PingFang should not be first for English locale"))
        // STSong should not be in English list
        #expect(!fonts.contains("STSong"), Comment(rawValue: "STSong should not be in English font list"))
        #expect(!fonts.contains("Heiti SC"), Comment(rawValue: "Heiti SC should not be in English font list"))
    }
}
