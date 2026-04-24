import Foundation
import GRDB

public struct ReadTheme: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "tb_themes"

    public var id: Int64?
    public var backgroundColor: String
    public var textColor: String
    public var backgroundImagePath: String

    enum CodingKeys: String, CodingKey {
        case id
        case backgroundColor = "background_color"
        case textColor = "text_color"
        case backgroundImagePath = "background_image_path"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public static let defaultLight = ReadTheme(
        id: nil,
        backgroundColor: "FFFBFBF3",
        textColor: "FF343434",
        backgroundImagePath: ""
    )

    public static let defaultDark = ReadTheme(
        id: nil,
        backgroundColor: "FF1A1A2E",
        textColor: "FFE0E0E0",
        backgroundImagePath: ""
    )

    public static let defaultSepia = ReadTheme(
        id: nil,
        backgroundColor: "FFFAF4E8",
        textColor: "FF121212",
        backgroundImagePath: ""
    )

    /// OLED-friendly night preset: pure black background with dimmed
    /// mid-grey text. Distinct from `defaultDark` (which uses a softer
    /// near-black, RGB 0.10/0.10/0.18). Night aims to minimise emissive
    /// backlight on OLED screens while keeping the foreground gentle on
    /// the eyes (no harsh pure white).
    public static let defaultNight = ReadTheme(
        id: nil,
        backgroundColor: "FF000000",
        textColor: "FFA0A0A0",
        backgroundImagePath: ""
    )
}
