import Foundation

/// Lightweight localization helper used across packages.
///
/// Looks up keys from the App's `Localizable.xcstrings` catalog. Falls back to
/// the supplied `value` when the key is not found in the bundle, so callers can
/// always supply a sensible English default.
public enum AppLocalization {
    /// Returns the localized string for the given key, or `value` if not found.
    public static func string(_ key: String, value: String) -> String {
        let main = Bundle.main.localizedString(forKey: key, value: value, table: nil)
        if main != key {
            return main
        }
        // Fall back to all loaded bundles (helps tests and previews where
        // the main bundle does not contain the catalog).
        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            let candidate = bundle.localizedString(forKey: key, value: value, table: nil)
            if candidate != key {
                return candidate
            }
        }
        return value
    }

    /// Returns a localized format string applied with the given CVarArg arguments.
    public static func format(_ key: String, _ value: String, _ arguments: CVarArg...) -> String {
        let template = string(key, value: value)
        return String(format: template, arguments: arguments)
    }
}
