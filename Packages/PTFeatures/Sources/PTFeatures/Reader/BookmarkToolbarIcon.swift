import Foundation

/// Centralized glyph + accessibility key selection for the reader
/// bookmark toolbar button. Both the PDF and EPUB reader hosts use
/// these mappings so a11y labels and icons never drift apart.
public enum BookmarkToolbarIcon {
    public static func systemName(isBookmarked: Bool) -> String {
        isBookmarked ? "bookmark.fill" : "bookmark"
    }

    public static func accessibilityKey(isBookmarked: Bool) -> String {
        isBookmarked ? "reader.toolbar.bookmark.remove" : "reader.toolbar.bookmark.add"
    }
}
