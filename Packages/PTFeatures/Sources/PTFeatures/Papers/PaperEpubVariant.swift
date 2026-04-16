import Foundation

/// Variants of the EPUB artifact served by the PaperTok detail API.
///
/// Papers may expose the EPUB in up to four flavors: an untagged default
/// (`epubUrl`), Chinese (`epubUrlZh`), English (`epubUrlEn`), and a bilingual
/// build (`epubUrlBilingual`). The picker surfaces only the variants present on
/// a given paper; when only one is available the detail view downloads directly
/// without showing a menu.
public enum PaperEpubVariant: String, Hashable, Sendable, CaseIterable {
    case `default`
    case chinese
    case english
    case bilingual

    /// Catalog key resolving to the label displayed in the variant picker.
    public var titleKey: String {
        switch self {
        case .default: return "papers.detail.epub_variant.default"
        case .chinese: return "papers.detail.epub_variant.chinese"
        case .english: return "papers.detail.epub_variant.english"
        case .bilingual: return "papers.detail.epub_variant.bilingual"
        }
    }
}
