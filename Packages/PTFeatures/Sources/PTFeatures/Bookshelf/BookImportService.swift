import Foundation
import PDFKit
import CryptoKit
import PTCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum BookImportError: Error, LocalizedError, Sendable {
    case unsupportedFormat
    case alreadyExists(Book)
    case copyFailed(Error)
    case saveFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Only PDF and EPUB files are supported."
        case .alreadyExists: return "This book is already in your library."
        case .copyFailed(let e): return "Could not copy file: \(e.localizedDescription)"
        case .saveFailed(let e): return "Could not save book: \(e.localizedDescription)"
        }
    }
}

public actor BookImportService {
    private let bookDAO: BookDAO
    private let booksDirectory: URL
    private let coversDirectory: URL

    public init(database: AppDatabase) {
        self.bookDAO = BookDAO(database: database)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.booksDirectory = docs.appendingPathComponent("Books", isDirectory: true)
        self.coversDirectory = docs.appendingPathComponent("Covers", isDirectory: true)
    }

    /// Import a book file from `sourceURL`.
    /// Returns the saved `Book`. Throws `BookImportError` on failure.
    public func importFile(from sourceURL: URL) async throws -> Book {
        // 1. Validate extension
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "pdf" || ext == "epub" else {
            throw BookImportError.unsupportedFormat
        }

        // 2. Prepare directories
        try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)

        // 3. Compute MD5 for deduplication
        let md5 = try computeMD5(at: sourceURL)
        if let existing = try await bookDAO.fetchByMD5(md5) {
            throw BookImportError.alreadyExists(existing)
        }

        // 4. Copy file to Books directory (unique name)
        let destName = "\(UUID().uuidString).\(ext)"
        let destURL = booksDirectory.appendingPathComponent(destName)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            throw BookImportError.copyFailed(error)
        }

        // 5. Extract metadata & generate cover
        let (title, author, _) = extractPDFMetadata(
            at: destURL,
            fallbackName: sourceURL.deletingPathExtension().lastPathComponent
        )
        let coverPath = generatePDFCover(at: destURL, md5: md5)

        // 6. Create and save Book record
        var book = Book.placeholder(title: title, filePath: destURL.path)
        book.author = author
        book.coverPath = coverPath
        book.md5 = md5
        do {
            return try await bookDAO.save(book)
        } catch {
            try? FileManager.default.removeItem(at: destURL)
            throw BookImportError.saveFailed(error)
        }
    }

    // MARK: - Private helpers

    private func computeMD5(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func extractPDFMetadata(at url: URL, fallbackName: String) -> (title: String, author: String, pageCount: Int) {
        guard let doc = PDFDocument(url: url) else {
            return (fallbackName, "", 0)
        }
        let attrs = doc.documentAttributes ?? [:]
        let rawTitle = (attrs[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespaces)
        let author = (attrs[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespaces)
        return (
            (rawTitle?.isEmpty ?? true) ? fallbackName : rawTitle!,
            author ?? "",
            doc.pageCount
        )
    }

    /// Renders the first PDF page as a PNG thumbnail. Returns the cover filename.
    private func generatePDFCover(at url: URL, md5: String) -> String {
        let coverName = "\(md5)_cover.png"
        let coverURL = coversDirectory.appendingPathComponent(coverName)

        guard !FileManager.default.fileExists(atPath: coverURL.path),
              let doc = PDFDocument(url: url),
              let firstPage = doc.page(at: 0) else {
            return coverName
        }

        let bounds = firstPage.bounds(for: .mediaBox)
        let scale: CGFloat = 1.5
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0 else { return coverName }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return coverName
        }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        firstPage.draw(with: .mediaBox, to: ctx)

        guard let cgImage = ctx.makeImage() else { return coverName }

#if canImport(UIKit)
        let uiImage = UIImage(cgImage: cgImage)
        if let pngData = uiImage.pngData() {
            try? pngData.write(to: coverURL)
        }
#elseif canImport(AppKit)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        if let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: coverURL)
        }
#endif
        return coverName
    }
}
