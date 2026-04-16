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
        `default`(locale: .autoupdatingCurrent)
    }

    public static func `default`(locale: Locale) -> BookStyle {
        BookStyle(
            id: nil,
            fontSize: 1.4,
            fontFamily: preferredDefaultFontFamily(locale: locale),
            lineHeight: 1.8,
            letterSpacing: 0.0,
            wordSpacing: 0.0,
            paragraphSpacing: 1.0,
            sideMargin: 6.0,
            topMargin: 90.0,
            bottomMargin: 50.0
        )
    }

    public static func defaultStyle(for locale: Locale = .autoupdatingCurrent) -> BookStyle {
        `default`(locale: locale)
    }

    public static func preferredDefaultFontFamily(locale: Locale = .autoupdatingCurrent) -> String {
        preferredFontFamilies(locale: locale).first ?? "Arial"
    }

    public static func preferredFontFamilies(locale: Locale = .autoupdatingCurrent) -> [String] {
        let base = [
            "Arial",
            "Georgia",
            "Palatino",
            "Iowan Old Style",
            "Source Han Serif SC"
        ]

        switch chineseScript(for: locale) {
        case .simplified:
            return unique([
                ".PingFang SC", "PingFang SC",
                "Songti SC", "STSong",
                "Heiti SC",
            ] + base)
        case .traditional:
            return unique([
                ".PingFang TC", "PingFang TC",
                ".PingFang HK",
                "Songti TC", "STSong",
                "Heiti TC",
            ] + base)
        case .none:
            return unique(base)
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func chineseScript(for locale: Locale) -> ChineseScript? {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        guard identifier.hasPrefix("zh") else { return nil }
        if identifier.contains("hant") || identifier.contains("tw") || identifier.contains("hk") || identifier.contains("mo") {
            return .traditional
        }
        return .simplified
    }

    private enum ChineseScript {
        case simplified
        case traditional
    }
}
