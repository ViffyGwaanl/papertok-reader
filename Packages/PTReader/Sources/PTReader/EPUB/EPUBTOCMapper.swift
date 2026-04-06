import Foundation
import ReadiumShared

/// Converts a Readium Link tree (table of contents) into a flat array of ChapterEntry.
public enum EPUBTOCMapper {
    /// Recursively flatten a Readium TOC link tree into an ordered ChapterEntry list.
    ///
    /// Each `Link` in the tree becomes a `ChapterEntry` with its nesting `level`.
    /// Children are placed immediately after their parent.
    public static func map(links: [Link], level: Int = 0) -> [ChapterEntry] {
        var result: [ChapterEntry] = []
        for link in links {
            let children = link.children
            result.append(ChapterEntry(
                title: link.title ?? link.href,
                href: link.href,
                level: level,
                childCount: children.count
            ))
            if !children.isEmpty {
                result.append(contentsOf: map(links: children, level: level + 1))
            }
        }
        return result
    }
}
