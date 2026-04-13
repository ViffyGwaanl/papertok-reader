import Foundation
import PTCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders a collection of `BookNote` records to a shareable PDF file.
///
/// Layout:
/// - Header page: book title + export timestamp.
/// - Each note: colored highlight bar, content, chapter reference, timestamp.
/// - Footer: page number.
public actor NotesPDFExportService {
    public init() {}

    public enum ExportError: Error, LocalizedError, Sendable {
        case noData
        case renderingFailed
        case writeFailed(Error)
        case unsupportedPlatform

        public var errorDescription: String? {
            switch self {
            case .noData:
                return AppLocalization.string(
                    "errors.notes.pdf.no_data",
                    value: "No notes to export."
                )
            case .renderingFailed:
                return AppLocalization.string(
                    "errors.notes.pdf.render_failed",
                    value: "Failed to render PDF."
                )
            case .writeFailed(let e):
                return AppLocalization.format(
                    "errors.notes.pdf.write_failed_format",
                    "Failed to write PDF: %@",
                    e.localizedDescription
                )
            case .unsupportedPlatform:
                return AppLocalization.string(
                    "errors.notes.pdf.unsupported_platform",
                    value: "PDF export is not supported on this platform."
                )
            }
        }
    }

    public struct Layout: Sendable {
        public let pageSize: CGSize
        public let margin: CGFloat
        public let titleFontSize: CGFloat
        public let subtitleFontSize: CGFloat
        public let bodyFontSize: CGFloat
        public let captionFontSize: CGFloat
        public let lineSpacing: CGFloat
        public let noteSpacing: CGFloat

        public init(
            pageSize: CGSize = CGSize(width: 612, height: 792), // US Letter
            margin: CGFloat = 48,
            titleFontSize: CGFloat = 22,
            subtitleFontSize: CGFloat = 14,
            bodyFontSize: CGFloat = 12,
            captionFontSize: CGFloat = 10,
            lineSpacing: CGFloat = 4,
            noteSpacing: CGFloat = 16
        ) {
            self.pageSize = pageSize
            self.margin = margin
            self.titleFontSize = titleFontSize
            self.subtitleFontSize = subtitleFontSize
            self.bodyFontSize = bodyFontSize
            self.captionFontSize = captionFontSize
            self.lineSpacing = lineSpacing
            self.noteSpacing = noteSpacing
        }

        public static let `default` = Layout()
    }

    /// Export notes to a PDF file at the given URL.
    public func exportNotes(
        _ notes: [BookNote],
        for book: Book,
        to url: URL,
        layout: Layout = .default
    ) async throws {
        guard notes.isEmpty == false else { throw ExportError.noData }

        let data: Data
        do {
            data = try renderPDFData(notes: notes, book: book, layout: layout)
        } catch let error as ExportError {
            throw error
        } catch {
            throw ExportError.renderingFailed
        }

        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ExportError.writeFailed(error)
        }
    }

    // MARK: - Rendering

    private func renderPDFData(
        notes: [BookNote],
        book: Book,
        layout: Layout
    ) throws -> Data {
        #if canImport(UIKit)
        let bounds = CGRect(origin: .zero, size: layout.pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            drawPages(notes: notes, book: book, layout: layout, ctx: ctx, bounds: bounds)
        }
        #else
        throw ExportError.unsupportedPlatform
        #endif
    }

    #if canImport(UIKit)
    private func drawPages(
        notes: [BookNote],
        book: Book,
        layout: Layout,
        ctx: UIGraphicsPDFRendererContext,
        bounds: CGRect
    ) {
        var pageIndex = 1
        ctx.beginPage()
        var y: CGFloat = layout.margin

        y = drawHeader(book: book, at: y, in: bounds, layout: layout)
        y += layout.noteSpacing

        for note in notes {
            let requiredHeight = estimateNoteHeight(note, in: bounds, layout: layout)
            if y + requiredHeight > bounds.height - layout.margin - 30 {
                drawFooter(pageNumber: pageIndex, in: bounds, layout: layout)
                pageIndex += 1
                ctx.beginPage()
                y = layout.margin
            }

            y = drawNote(note, at: y, in: bounds, layout: layout)
            y += layout.noteSpacing
        }

        drawFooter(pageNumber: pageIndex, in: bounds, layout: layout)
    }

    private func drawHeader(
        book: Book,
        at y: CGFloat,
        in bounds: CGRect,
        layout: Layout
    ) -> CGFloat {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: layout.titleFontSize, weight: .bold),
            .foregroundColor: UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: layout.subtitleFontSize, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        let contentWidth = bounds.width - 2 * layout.margin

        let title = NSAttributedString(string: book.title, attributes: titleAttrs)
        let titleRect = CGRect(x: layout.margin, y: y, width: contentWidth, height: 30)
        title.draw(in: titleRect)

        let author = book.author.isEmpty ? "" : "by \(book.author)  ·  "
        let dateString = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)
        let subtitle = NSAttributedString(
            string: "\(author)Exported \(dateString)",
            attributes: subtitleAttrs
        )
        let subtitleRect = CGRect(x: layout.margin, y: y + 30, width: contentWidth, height: 20)
        subtitle.draw(in: subtitleRect)

        // Separator line
        let separatorY = y + 54
        let path = UIBezierPath()
        path.move(to: CGPoint(x: layout.margin, y: separatorY))
        path.addLine(to: CGPoint(x: bounds.width - layout.margin, y: separatorY))
        UIColor(red: 0.85, green: 0.82, blue: 0.78, alpha: 1).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        return separatorY + 8
    }

    private func drawNote(
        _ note: BookNote,
        at y: CGFloat,
        in bounds: CGRect,
        layout: Layout
    ) -> CGFloat {
        let contentX = layout.margin + 10
        let contentWidth = bounds.width - 2 * layout.margin - 14

        let contentAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: layout.bodyFontSize),
            .foregroundColor: UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        ]
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: layout.captionFontSize),
            .foregroundColor: UIColor.gray
        ]

        let contentString = NSAttributedString(string: note.content, attributes: contentAttrs)
        let contentSize = contentString.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let contentHeight = ceil(contentSize.height)

        // Highlight bar
        let barRect = CGRect(x: layout.margin, y: y, width: 4, height: max(contentHeight, 20))
        let barColor = highlightColor(for: note.color)
        barColor.setFill()
        UIBezierPath(roundedRect: barRect, cornerRadius: 2).fill()

        // Content
        contentString.draw(in: CGRect(x: contentX, y: y, width: contentWidth, height: contentHeight))

        var cursorY = y + contentHeight + 2

        // Chapter + timestamp
        var captionParts: [String] = []
        if note.chapter.isEmpty == false {
            captionParts.append(note.chapter)
        }
        let dateSource = note.createTime ?? note.updateTime
        captionParts.append(
            DateFormatter.localizedString(from: dateSource, dateStyle: .medium, timeStyle: .short)
        )
        let caption = NSAttributedString(
            string: captionParts.joined(separator: "  ·  "),
            attributes: captionAttrs
        )
        caption.draw(in: CGRect(x: contentX, y: cursorY, width: contentWidth, height: 14))
        cursorY += 16

        if let readerNote = note.readerNote, readerNote.isEmpty == false {
            let noteAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: layout.bodyFontSize),
                .foregroundColor: UIColor.darkGray
            ]
            let noteString = NSAttributedString(string: "Note: \(readerNote)", attributes: noteAttrs)
            let noteBoundingSize = noteString.boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            let nh = ceil(noteBoundingSize.height)
            noteString.draw(in: CGRect(x: contentX, y: cursorY, width: contentWidth, height: nh))
            cursorY += nh + 2
        }

        return cursorY
    }

    private func drawFooter(
        pageNumber: Int,
        in bounds: CGRect,
        layout: Layout
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: layout.captionFontSize),
            .foregroundColor: UIColor.gray
        ]
        let string = NSAttributedString(string: "Page \(pageNumber)", attributes: attrs)
        let size = string.size()
        let rect = CGRect(
            x: (bounds.width - size.width) / 2,
            y: bounds.height - layout.margin / 2 - size.height,
            width: size.width,
            height: size.height
        )
        string.draw(in: rect)
    }

    private func estimateNoteHeight(
        _ note: BookNote,
        in bounds: CGRect,
        layout: Layout
    ) -> CGFloat {
        let contentWidth = bounds.width - 2 * layout.margin - 14
        let contentAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: layout.bodyFontSize)
        ]
        let h = NSAttributedString(string: note.content, attributes: contentAttrs)
            .boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            .height
        var total = ceil(h) + 20 // content + caption row
        if let readerNote = note.readerNote, readerNote.isEmpty == false {
            let nh = NSAttributedString(string: readerNote, attributes: contentAttrs)
                .boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                .height
            total += ceil(nh) + 4
        }
        return total
    }

    private func highlightColor(for stored: String) -> UIColor {
        let hex = NoteColorResolver.normalizedHex(for: stored)
        return UIColor(hexString: hex) ?? UIColor(red: 0.56, green: 0.65, blue: 0.54, alpha: 1)
    }
    #endif
}

#if canImport(UIKit)
private extension UIColor {
    convenience init?(hexString: String) {
        var trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.replacingOccurrences(of: "#", with: "")
        guard trimmed.count == 6, let int = UInt32(trimmed, radix: 16) else { return nil }
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
#endif
