import Foundation

public enum DateFormatting {
    public static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public static func formatDuration(seconds: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar

        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds / 60)"
    }

    /// Format a Date as a "yyyy-MM-dd" string.
    public static func dateString(from date: Date) -> String {
        dateOnly.string(from: date)
    }

    /// Parse a "yyyy-MM-dd" string back into a Date.
    public static func date(from string: String) -> Date? {
        dateOnly.date(from: string)
    }
}
