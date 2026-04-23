import Foundation
import PTReader

/// Locale-aware filter for reader TOC entries.
///
/// The filter is pure and synchronous so it can be reused from both the
/// PDF and EPUB TOC panels and exercised from unit tests without any
/// Readium / PDFKit setup.
///
/// Matching rules:
/// - Empty / whitespace-only query returns the full list.
/// - Non-empty query uses `String.localizedStandardContains(_:)` which is
///   case-insensitive, diacritic-insensitive and works naturally with
///   CJK substrings, so "深入" correctly matches "第三章 深入探索".
public enum TOCSearchFilter {
    public static func filter(_ entries: [ChapterEntry], query: String) -> [ChapterEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return entries }
        return entries.filter { $0.title.localizedStandardContains(trimmed) }
    }
}
