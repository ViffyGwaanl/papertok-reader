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

    // MARK: - W6.3a additions (column count / writing mode / threshold)

    public var maxColumnCount: ColumnCount
    public var columnThreshold: Double
    public var writingMode: WritingMode

    // MARK: - W6.3b additions (reading info overlay)

    /// Describes what is displayed in each of the 6 reader header/footer
    /// slots (top-left/top-center/top-right + bottom-left/bottom-center/bottom-right).
    public var readingInfo: ReadingInfoLayout

    // MARK: - W7.1 additions (reader immersion)

    /// Number of seconds before the reader chrome (toolbar + info overlay +
    /// status bar) fades out automatically after the user interacts. A value
    /// of `0` disables auto-hide — chrome stays visible until manually
    /// toggled.
    public var autoHideChromeSeconds: Double

    /// Number of columns displayed in reflowable EPUB content.
    public enum ColumnCount: String, Codable, CaseIterable, Sendable {
        case auto
        case single
        case double
    }

    /// Writing progression mode for the publication.
    public enum WritingMode: String, Codable, CaseIterable, Sendable {
        case auto
        case horizontalTb
        case verticalRl
    }

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
        case maxColumnCount = "max_column_count"
        case columnThreshold = "column_threshold"
        case writingMode = "writing_mode"
        case readingInfo = "reading_info"
        case autoHideChromeSeconds = "auto_hide_chrome_seconds"
    }

    public init(
        id: Int64? = nil,
        fontSize: Double,
        fontFamily: String,
        lineHeight: Double,
        letterSpacing: Double,
        wordSpacing: Double,
        paragraphSpacing: Double,
        sideMargin: Double,
        topMargin: Double,
        bottomMargin: Double,
        maxColumnCount: ColumnCount = .auto,
        columnThreshold: Double = 800,
        writingMode: WritingMode = .auto,
        readingInfo: ReadingInfoLayout = .default,
        autoHideChromeSeconds: Double = 3.0
    ) {
        self.id = id
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.wordSpacing = wordSpacing
        self.paragraphSpacing = paragraphSpacing
        self.sideMargin = sideMargin
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
        self.maxColumnCount = maxColumnCount
        self.columnThreshold = columnThreshold
        self.writingMode = writingMode
        self.readingInfo = readingInfo
        self.autoHideChromeSeconds = autoHideChromeSeconds
    }

    // MARK: - Backward-compat Codable

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(Int64.self, forKey: .id)
        self.fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 1.4
        self.fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? BookStyle.preferredDefaultFontFamily()
        self.lineHeight = try c.decodeIfPresent(Double.self, forKey: .lineHeight) ?? 1.8
        self.letterSpacing = try c.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? 0.0
        self.wordSpacing = try c.decodeIfPresent(Double.self, forKey: .wordSpacing) ?? 0.0
        self.paragraphSpacing = try c.decodeIfPresent(Double.self, forKey: .paragraphSpacing) ?? 1.0
        self.sideMargin = try c.decodeIfPresent(Double.self, forKey: .sideMargin) ?? 6.0
        self.topMargin = try c.decodeIfPresent(Double.self, forKey: .topMargin) ?? 90.0
        self.bottomMargin = try c.decodeIfPresent(Double.self, forKey: .bottomMargin) ?? 50.0
        self.maxColumnCount = try c.decodeIfPresent(ColumnCount.self, forKey: .maxColumnCount) ?? .auto
        self.columnThreshold = try c.decodeIfPresent(Double.self, forKey: .columnThreshold) ?? 800
        self.writingMode = try c.decodeIfPresent(WritingMode.self, forKey: .writingMode) ?? .auto
        self.readingInfo = try c.decodeIfPresent(ReadingInfoLayout.self, forKey: .readingInfo) ?? .default
        self.autoHideChromeSeconds = try c.decodeIfPresent(Double.self, forKey: .autoHideChromeSeconds) ?? 3.0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(fontFamily, forKey: .fontFamily)
        try c.encode(lineHeight, forKey: .lineHeight)
        try c.encode(letterSpacing, forKey: .letterSpacing)
        try c.encode(wordSpacing, forKey: .wordSpacing)
        try c.encode(paragraphSpacing, forKey: .paragraphSpacing)
        try c.encode(sideMargin, forKey: .sideMargin)
        try c.encode(topMargin, forKey: .topMargin)
        try c.encode(bottomMargin, forKey: .bottomMargin)
        try c.encode(maxColumnCount, forKey: .maxColumnCount)
        try c.encode(columnThreshold, forKey: .columnThreshold)
        try c.encode(writingMode, forKey: .writingMode)
        try c.encode(readingInfo, forKey: .readingInfo)
        try c.encode(autoHideChromeSeconds, forKey: .autoHideChromeSeconds)
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
            bottomMargin: 50.0,
            maxColumnCount: .auto,
            columnThreshold: 800,
            writingMode: .auto,
            readingInfo: .default,
            autoHideChromeSeconds: 3.0
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
