import Foundation
import Testing
@testable import PTFeatures
import PTReader

@Suite("ReaderImageAnalysisPrompt")
struct ReaderImageAnalysisPromptTests {
    @Test("build includes localized book, chapter, and image metadata when available")
    func buildIncludesContextualMetadata() {
        let asset = ReaderImageAsset(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            mimeType: "image/png",
            title: "Microscopy Plate",
            altText: "Cell sample",
            sourceURL: "chapter-2.xhtml#figure-3"
        )
        let locale = Locale(identifier: "zh-Hans")

        let prompt = ReaderImageAnalysisPrompt.build(
            for: asset,
            bookTitle: "PaperTok Reader Design",
            chapterTitle: "第 2 章",
            locale: locale
        )

        #expect(prompt.contains(localizedCatalogFormat("reader.image_analysis.prompt.intro", locale: locale, "PaperTok Reader Design")))
        #expect(prompt.contains(localizedCatalogFormat("reader.image_analysis.prompt.chapter_format", locale: locale, "第 2 章")))
        #expect(prompt.contains(localizedCatalogFormat("reader.image_analysis.prompt.title_format", locale: locale, "Microscopy Plate")))
        #expect(prompt.contains(localizedCatalogFormat("reader.image_analysis.prompt.alt_text_format", locale: locale, "Cell sample")))
        #expect(prompt.contains(localizedCatalogFormat("reader.image_analysis.prompt.source_format", locale: locale, "chapter-2.xhtml#figure-3")))
    }

    @Test("build omits empty optional metadata")
    func buildOmitsBlankMetadata() {
        let asset = ReaderImageAsset(
            data: Data([0xFF, 0xD8, 0xFF]),
            mimeType: "image/jpeg",
            title: "",
            altText: nil,
            sourceURL: nil
        )

        let prompt = ReaderImageAnalysisPrompt.build(
            for: asset,
            bookTitle: "Book Title",
            chapterTitle: ""
        )

        #expect(
            prompt == localizedCatalogFormat(
                "reader.image_analysis.prompt.intro",
                "Book Title"
            )
        )
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
