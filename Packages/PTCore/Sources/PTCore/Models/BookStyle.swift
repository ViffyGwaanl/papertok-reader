import Foundation
import GRDB

public struct BookStyle: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "tb_styles"

    public var id: Int64?
    public var fontSize: Double
    public var fontFamily: String
    public var lineHeight: Double
    public var letterSpacing: Double
    public var wordSpacing: Double
    public var paragraphSpacing: Double
    public var sideMargin: Double
    public var topMargin: Double
    public var bottomMargin: Double

    enum CodingKeys: String, CodingKey {
        case id
        case fontSize = "font_size"
        case fontFamily = "font_family"
        case lineHeight = "line_height"
        case letterSpacing = "letter_spacing"
        case wordSpacing = "word_spacing"
        case paragraphSpacing = "paragraph_spacing"
        case sideMargin = "side_margin"
        case topMargin = "top_margin"
        case bottomMargin = "bottom_margin"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public static var `default`: BookStyle {
        defaultStyle()
    }

    public static func defaultStyle(for locale: Locale = .autoupdatingCurrent) -> BookStyle {
        BookStyle(
            id: nil,
            fontSize: 1.4,
            fontFamily: defaultFontFamily(for: locale),
            lineHeight: 1.8,
            letterSpacing: 0.0,
            wordSpacing: 0.0,
            paragraphSpacing: 1.0,
            sideMargin: 6.0,
            topMargin: 90.0,
            bottomMargin: 50.0
        )
    }

    public static func defaultFontFamily(for locale: Locale = .autoupdatingCurrent) -> String {
        if locale.isTraditionalChinese {
            return "Songti TC"
        }
        if locale.isChinese {
            return "Songti SC"
        }
        return "Arial"
    }

    public static func recommendedFontFamilies(for locale: Locale = .autoupdatingCurrent) -> [String] {
        let prioritizedChineseFonts: [String]
        if locale.isTraditionalChinese {
            prioritizedChineseFonts = ["Songti TC", "PingFang TC"]
        } else if locale.isChinese {
            prioritizedChineseFonts = ["Songti SC", "PingFang SC"]
        } else {
            prioritizedChineseFonts = []
        }

        let fallbackFonts = [
            "Arial",
            "Georgia",
            "Palatino",
            "Iowan Old Style",
            "Source Han Serif SC",
        ]

        return Array(NSOrderedSet(array: prioritizedChineseFonts + fallbackFonts)) as? [String] ?? (prioritizedChineseFonts + fallbackFonts)
    }
}

private extension Locale {
    var isChinese: Bool {
        identifier.lowercased().hasPrefix("zh")
    }

    var isTraditionalChinese: Bool {
        let lowered = identifier.lowercased()
        return lowered.contains("hant") || lowered.hasSuffix("_tw") || lowered.hasSuffix("_hk") || lowered.hasSuffix("_mo")
    }
}
