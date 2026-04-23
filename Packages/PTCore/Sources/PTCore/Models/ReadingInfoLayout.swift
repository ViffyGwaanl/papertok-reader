import Foundation

/// W6.3b — Reader header/footer display fields.
///
/// Mirrors the Flutter `ReadingInfoEnum` from
/// `lib/widgets/reading_page/more_settings/reading_settings.dart`, plus a
/// `clock` case that was missing in the original but is a natural fit
/// alongside battery level.
public enum ReadingInfoField: String, Codable, CaseIterable, Sendable {
    /// Nothing is shown in this slot.
    case nothing
    /// Current chapter title.
    case chapterTitle = "chapter_title"
    /// Page number, rendered as `"3 / 247"`.
    case pageNumber = "page_number"
    /// Reading progress percentage, rendered as `"12%"`.
    case progressPercentage = "progress_percentage"
    /// Elapsed time for the current session, rendered as `"1h 23m"`.
    case readingTime = "reading_time"
    /// Battery level, rendered as `"87%"`.
    case batteryLevel = "battery_level"
    /// Wall-clock time, rendered as `"15:42"`.
    case clock
}

/// Layout describing what to render in the 6 reader-chrome slots
/// (top-left / top-center / top-right + bottom-left / bottom-center / bottom-right).
public struct ReadingInfoLayout: Codable, Hashable, Sendable {
    public var topLeft: ReadingInfoField
    public var topCenter: ReadingInfoField
    public var topRight: ReadingInfoField
    public var bottomLeft: ReadingInfoField
    public var bottomCenter: ReadingInfoField
    public var bottomRight: ReadingInfoField

    public init(
        topLeft: ReadingInfoField = .nothing,
        topCenter: ReadingInfoField = .nothing,
        topRight: ReadingInfoField = .nothing,
        bottomLeft: ReadingInfoField = .nothing,
        bottomCenter: ReadingInfoField = .nothing,
        bottomRight: ReadingInfoField = .nothing
    ) {
        self.topLeft = topLeft
        self.topCenter = topCenter
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomCenter = bottomCenter
        self.bottomRight = bottomRight
    }

    /// Matches Flutter defaults: chapter title at top-center, page number
    /// at bottom-left, progress percentage at bottom-right.
    public static let `default`: ReadingInfoLayout = ReadingInfoLayout(
        topLeft: .nothing,
        topCenter: .chapterTitle,
        topRight: .nothing,
        bottomLeft: .pageNumber,
        bottomCenter: .nothing,
        bottomRight: .progressPercentage
    )

    enum CodingKeys: String, CodingKey {
        case topLeft = "top_left"
        case topCenter = "top_center"
        case topRight = "top_right"
        case bottomLeft = "bottom_left"
        case bottomCenter = "bottom_center"
        case bottomRight = "bottom_right"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.topLeft = try c.decodeIfPresent(ReadingInfoField.self, forKey: .topLeft) ?? .nothing
        self.topCenter = try c.decodeIfPresent(ReadingInfoField.self, forKey: .topCenter) ?? .chapterTitle
        self.topRight = try c.decodeIfPresent(ReadingInfoField.self, forKey: .topRight) ?? .nothing
        self.bottomLeft = try c.decodeIfPresent(ReadingInfoField.self, forKey: .bottomLeft) ?? .pageNumber
        self.bottomCenter = try c.decodeIfPresent(ReadingInfoField.self, forKey: .bottomCenter) ?? .nothing
        self.bottomRight = try c.decodeIfPresent(ReadingInfoField.self, forKey: .bottomRight) ?? .progressPercentage
    }
}
