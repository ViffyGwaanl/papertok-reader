import Foundation

public enum AppLocalization {
    public enum UserFacingErrorPriority {
        case preferLocalizedError
        case preferFallback
    }

    public static func string(
        _ key: String,
        bundle: Bundle = .main,
        locale: Locale? = nil,
        table: String? = nil,
        value: String? = nil
    ) -> String {
        if let explicitLocalized = explicitLocalizedString(
            key,
            bundle: bundle,
            locale: locale,
            table: table
        ) {
            return explicitLocalized
        }

        let resolvedBundle = localizedBundle(for: locale, in: bundle) ?? bundle
        let localized = resolvedBundle.localizedString(forKey: key, value: value, table: table)
        return localized == key ? bundle.localizedString(forKey: key, value: value, table: table) : localized
    }

    public static func format(
        _ key: String,
        bundle: Bundle = .main,
        locale: Locale? = nil,
        table: String? = nil,
        _ arguments: CVarArg...
    ) -> String {
        let format = string(key, bundle: bundle, locale: locale, table: table)
        return String(format: format, locale: locale ?? .autoupdatingCurrent, arguments: arguments)
    }

    public static func format(
        _ key: String,
        fallback: String,
        bundle: Bundle = .main,
        locale: Locale? = nil,
        table: String? = nil,
        _ arguments: CVarArg...
    ) -> String {
        let format = string(
            key,
            bundle: bundle,
            locale: locale,
            table: table,
            value: fallback
        )
        return String(format: format, locale: locale ?? .autoupdatingCurrent, arguments: arguments)
    }

    public static func localizedErrorDescription(_ error: Error) -> String? {
        guard let localizedError = error as? LocalizedError,
              let errorDescription = localizedError.errorDescription,
              errorDescription.isEmpty == false else {
            return nil
        }

        return errorDescription
    }

    public static func errorDetail(_ error: Error) -> String {
        localizedErrorDescription(error) ?? error.localizedDescription
    }

    public static func userFacingErrorMessage(
        for error: Error,
        fallbackKey: String,
        bundle: Bundle = .main,
        locale: Locale? = nil,
        table: String? = nil,
        priority: UserFacingErrorPriority = .preferLocalizedError
    ) -> String {
        switch priority {
        case .preferLocalizedError:
            if let description = localizedErrorDescription(error) {
                return description
            }
        case .preferFallback:
            break
        }

        return string(
            fallbackKey,
            bundle: bundle,
            locale: locale,
            table: table
        )
    }

    public static func userFacingErrorMessage(
        for error: Error,
        fallbackKey: String,
        fallback: String,
        bundle: Bundle = .main,
        locale: Locale? = nil,
        table: String? = nil,
        priority: UserFacingErrorPriority = .preferLocalizedError
    ) -> String {
        switch priority {
        case .preferLocalizedError:
            if let description = localizedErrorDescription(error) {
                return description
            }
        case .preferFallback:
            break
        }

        return string(
            fallbackKey,
            bundle: bundle,
            locale: locale,
            table: table,
            value: fallback
        )
    }

    private static func localizedBundle(for locale: Locale?, in bundle: Bundle) -> Bundle? {
        guard let locale else { return nil }

        for identifier in localizationCandidates(for: locale) {
            if let path = bundle.path(forResource: identifier, ofType: "lproj"),
               let localizedBundle = Bundle(path: path) {
                return localizedBundle
            }
        }

        return nil
    }

    private static func explicitLocalizedString(
        _ key: String,
        bundle: Bundle,
        locale: Locale?,
        table: String?
    ) -> String? {
        guard let locale else { return nil }

        let tableName = table ?? "Localizable"
        for identifier in localizationCandidates(for: locale) {
            guard let url = bundle.url(
                forResource: tableName,
                withExtension: "strings",
                subdirectory: nil,
                localization: identifier
            ) else {
                continue
            }

            if let dictionary = NSDictionary(contentsOf: url) as? [String: String],
               let localized = dictionary[key] {
                return localized
            }
        }

        return nil
    }

    private static func localizationCandidates(for locale: Locale) -> [String] {
        let normalized = locale.identifier.replacingOccurrences(of: "_", with: "-")
        var candidates: [String] = []

        func append(_ identifier: String) {
            guard !identifier.isEmpty, !candidates.contains(identifier) else { return }
            candidates.append(identifier)
        }

        append(normalized)

        let lowercased = normalized.lowercased()
        if lowercased.hasPrefix("zh") {
            if lowercased.contains("hant") || lowercased.contains("tw") || lowercased.contains("hk") || lowercased.contains("mo") {
                append("zh-Hant")
                append("zh-TW")
            } else {
                append("zh-Hans")
                append("zh-CN")
            }
        }

        let components = normalized.split(separator: "-")
        if components.count > 1 {
            append(String(components[0]))
        }

        return candidates
    }
}
