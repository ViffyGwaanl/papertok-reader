import Foundation

public enum LocalizedSort {
    public static func compare(
        _ lhs: String,
        _ rhs: String,
        locale: Locale = .autoupdatingCurrent
    ) -> ComparisonResult {
        sortKey(for: lhs, locale: locale).compare(sortKey(for: rhs, locale: locale))
    }

    public static func isAscending(
        _ lhs: String,
        _ rhs: String,
        locale: Locale = .autoupdatingCurrent
    ) -> Bool {
        compare(lhs, rhs, locale: locale) == .orderedAscending
    }

    public static func sortKey(
        for value: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let base = isChinese(locale: locale) ? mandarinLatin(value) : value
        return base
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            .replacingOccurrences(of: " ", with: "")
            .lowercased(with: locale)
    }

    private static func mandarinLatin(_ value: String) -> String {
        let mutable = NSMutableString(string: value) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return mutable as String
    }

    private static func isChinese(locale: Locale) -> Bool {
        locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased().hasPrefix("zh")
    }
}
