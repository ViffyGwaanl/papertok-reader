import Foundation
import PTReader

public enum ReaderImageAnalysisPrompt {
    public static func build(
        for asset: ReaderImageAsset,
        bookTitle: String,
        chapterTitle: String?,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        var lines = [
            localizedCatalogFormat(
                "reader.image_analysis.prompt.intro",
                locale: locale,
                bookTitle
            )
        ]

        if let chapterTitle = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines), chapterTitle.isEmpty == false {
            lines.append(
                localizedCatalogFormat(
                    "reader.image_analysis.prompt.chapter_format",
                    locale: locale,
                    chapterTitle
                )
            )
        }
        if let title = asset.title, title.isEmpty == false {
            lines.append(
                localizedCatalogFormat(
                    "reader.image_analysis.prompt.title_format",
                    locale: locale,
                    title
                )
            )
        }
        if let altText = asset.altText, altText.isEmpty == false {
            lines.append(
                localizedCatalogFormat(
                    "reader.image_analysis.prompt.alt_text_format",
                    locale: locale,
                    altText
                )
            )
        }
        if let sourceURL = asset.sourceURL, sourceURL.isEmpty == false {
            lines.append(
                localizedCatalogFormat(
                    "reader.image_analysis.prompt.source_format",
                    locale: locale,
                    sourceURL
                )
            )
        }

        return lines.joined(separator: " ")
    }
}

private func localizedCatalogString(_ key: String, locale: Locale = .autoupdatingCurrent) -> String {
    String(localized: String.LocalizationValue(key), bundle: localizedCatalogBundle(), locale: locale)
}

private func localizedCatalogFormat(_ key: String, locale: Locale = .autoupdatingCurrent, _ arguments: CVarArg...) -> String {
    String(format: localizedCatalogString(key, locale: locale), locale: locale, arguments: arguments)
}

private func localizedCatalogBundle() -> Bundle {
    let bundles = Bundle.allBundles + Bundle.allFrameworks

    if Bundle.main.bundleURL.pathExtension == "app" {
        return .main
    }
    if let appBundle = bundles.first(where: { $0.bundleIdentifier == "ai.papertok.paperreader" }) {
        return appBundle
    }
    let candidateDirectories = Set(bundles.map { $0.bundleURL.deletingLastPathComponent() })
    for directory in candidateDirectories {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { continue }

        for candidateURL in urls where candidateURL.pathExtension == "app" {
            if let appBundle = Bundle(url: candidateURL),
               appBundle.bundleIdentifier == "ai.papertok.paperreader" {
                return appBundle
            }
        }
    }
    return bundles.first(where: { $0.bundleURL.pathExtension == "app" }) ?? .main
}
