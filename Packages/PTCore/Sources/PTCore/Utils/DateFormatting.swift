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

    public static func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
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
