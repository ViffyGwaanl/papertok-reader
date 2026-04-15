import Foundation

public struct PDFOutlineChapter: Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let pageIndex: Int
    public let depth: Int
    public let children: [PDFOutlineChapter]

    public init(
        id: String,
        title: String,
        pageIndex: Int,
        depth: Int,
        children: [PDFOutlineChapter] = []
    ) {
        self.id = id
        self.title = title
        self.pageIndex = pageIndex
        self.depth = depth
        self.children = children
    }
}

extension PDFOutlineChapter {
    /// Depth-first flatten preserving document order. Children follow their parent.
    public func flattened() -> [PDFOutlineChapter] {
        var out: [PDFOutlineChapter] = [self]
        for child in children {
            out.append(contentsOf: child.flattened())
        }
        return out
    }
}

extension Array where Element == PDFOutlineChapter {
    public func flattened() -> [PDFOutlineChapter] {
        flatMap { $0.flattened() }
    }
}
