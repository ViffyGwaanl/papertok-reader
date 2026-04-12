#if canImport(PDFKit)
import CoreGraphics
import Foundation
import PDFKit
import PTCore

public struct PDFAnnotationAnchor: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case selection
        case bookmark
    }

    public struct Rect: Codable, Equatable, Sendable {
        public let pageIndex: Int
        public let normalizedX: Double
        public let normalizedY: Double
        public let normalizedWidth: Double
        public let normalizedHeight: Double

        public init(
            pageIndex: Int,
            normalizedX: Double,
            normalizedY: Double,
            normalizedWidth: Double,
            normalizedHeight: Double
        ) {
            self.pageIndex = pageIndex
            self.normalizedX = normalizedX
            self.normalizedY = normalizedY
            self.normalizedWidth = normalizedWidth
            self.normalizedHeight = normalizedHeight
        }
    }

    public let kind: Kind
    public let pageIndex: Int
    public let pageLabel: String
    public let rects: [Rect]

    public init(
        kind: Kind,
        pageIndex: Int,
        pageLabel: String,
        rects: [Rect]
    ) {
        self.kind = kind
        self.pageIndex = pageIndex
        self.pageLabel = pageLabel
        self.rects = rects
    }

    public static func bookmark(pageIndex: Int, pageLabel: String) -> Self {
        Self(kind: .bookmark, pageIndex: pageIndex, pageLabel: pageLabel, rects: [])
    }
}

public struct PDFRenderedAnnotation: Equatable, Sendable {
    public let noteID: Int64?
    public let pageIndex: Int
    public let bounds: CGRect
    public let type: NoteType
    public let colorHex: String
    public let readerNote: String?

    public init(
        noteID: Int64?,
        pageIndex: Int,
        bounds: CGRect,
        type: NoteType,
        colorHex: String,
        readerNote: String?
    ) {
        self.noteID = noteID
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.type = type
        self.colorHex = colorHex
        self.readerNote = readerNote
    }
}

public struct PDFSelectionSnapshot: Equatable, Sendable {
    public let selectedText: String
    public let anchorString: String
    public let pageLabel: String

    public init(selectedText: String, anchorString: String, pageLabel: String) {
        self.selectedText = selectedText
        self.anchorString = anchorString
        self.pageLabel = pageLabel
    }
}

public enum PDFAnnotationBridge {
    public static func selectionSnapshot(
        from selection: PDFSelection,
        in document: PDFDocument
    ) -> PDFSelectionSnapshot? {
        let trimmedText = (selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false,
              let anchor = anchor(from: selection, in: document) else {
            return nil
        }

        return PDFSelectionSnapshot(
            selectedText: trimmedText,
            anchorString: storedString(from: anchor),
            pageLabel: anchor.pageLabel
        )
    }

    public static func anchor(from selection: PDFSelection, in document: PDFDocument) -> PDFAnnotationAnchor? {
        let pages = selection.pages
        guard let firstPage = pages.first else {
            return nil
        }

        let pageIndex = document.index(for: firstPage)
        guard pageIndex >= 0 else {
            return nil
        }

        let rects = pages.compactMap { page -> PDFAnnotationAnchor.Rect? in
            let currentPageIndex = document.index(for: page)
            guard currentPageIndex >= 0 else {
                return nil
            }

            let pageBounds = page.bounds(for: .mediaBox)
            let selectionBounds = selection.bounds(for: page)
            guard pageBounds.width > 0,
                  pageBounds.height > 0,
                  selectionBounds.isNull == false,
                  selectionBounds.isEmpty == false else {
                return nil
            }

            return PDFAnnotationAnchor.Rect(
                pageIndex: currentPageIndex,
                normalizedX: Double((selectionBounds.minX - pageBounds.minX) / pageBounds.width),
                normalizedY: Double((selectionBounds.minY - pageBounds.minY) / pageBounds.height),
                normalizedWidth: Double(selectionBounds.width / pageBounds.width),
                normalizedHeight: Double(selectionBounds.height / pageBounds.height)
            )
        }

        guard rects.isEmpty == false else {
            return nil
        }

        return PDFAnnotationAnchor(
            kind: .selection,
            pageIndex: pageIndex,
            pageLabel: firstPage.label ?? "Page \(pageIndex + 1)",
            rects: rects
        )
    }

    public static func storedString(from anchor: PDFAnnotationAnchor) -> String {
        guard let data = try? JSONEncoder().encode(anchor),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    public static func anchor(fromStoredString stored: String) -> PDFAnnotationAnchor? {
        guard let data = stored.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(PDFAnnotationAnchor.self, from: data)
    }

    public static func renderedAnnotations(
        from note: BookNote,
        in document: PDFDocument
    ) -> [PDFRenderedAnnotation] {
        guard let anchor = anchor(fromStoredString: note.cfi) else {
            return []
        }

        let type = NoteType(rawValue: note.type) ?? .highlight
        let colorHex = note.color.isEmpty ? HighlightColor.yellow.hex : note.color

        switch anchor.kind {
        case .bookmark:
            guard let page = document.page(at: anchor.pageIndex) else {
                return []
            }

            return [
                PDFRenderedAnnotation(
                    noteID: note.id,
                    pageIndex: anchor.pageIndex,
                    bounds: bookmarkBounds(for: page.bounds(for: .mediaBox)),
                    type: .bookmark,
                    colorHex: colorHex,
                    readerNote: note.readerNote
                )
            ]

        case .selection:
            return anchor.rects.compactMap { rect in
                guard let page = document.page(at: rect.pageIndex) else {
                    return nil
                }

                let pageBounds = page.bounds(for: .mediaBox)
                guard pageBounds.width > 0,
                      pageBounds.height > 0 else {
                    return nil
                }

                let renderedBounds = CGRect(
                    x: pageBounds.minX + (pageBounds.width * rect.normalizedX),
                    y: pageBounds.minY + (pageBounds.height * rect.normalizedY),
                    width: pageBounds.width * rect.normalizedWidth,
                    height: pageBounds.height * rect.normalizedHeight
                )

                guard renderedBounds.isEmpty == false else {
                    return nil
                }

                return PDFRenderedAnnotation(
                    noteID: note.id,
                    pageIndex: rect.pageIndex,
                    bounds: renderedBounds,
                    type: type,
                    colorHex: colorHex,
                    readerNote: note.readerNote
                )
            }
        }
    }

    private static func bookmarkBounds(for pageBounds: CGRect) -> CGRect {
        let size = max(24, min(pageBounds.width * 0.08, 32))
        let inset = max(12, size * 0.5)
        return CGRect(
            x: pageBounds.maxX - size - inset,
            y: pageBounds.maxY - size - inset,
            width: size,
            height: size
        )
    }
}
#endif
