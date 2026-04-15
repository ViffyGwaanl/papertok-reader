import Foundation
import PTCore

#if canImport(PDFKit)
import PDFKit

#if canImport(Vision)
import Vision
#endif

/// BookContentBridge implementation for PDF documents using PDFKit.
@MainActor
public final class PDFContentBridge: BookContentBridge {
    public typealias OCRTextProvider = @Sendable @MainActor (Int) async throws -> String

    private let document: PDFDocument
    private let ocrTextProvider: OCRTextProvider?
    public let title: String

    public init(
        document: PDFDocument,
        title: String,
        ocrTextProvider: OCRTextProvider? = nil
    ) {
        self.document = document
        self.title = title
        self.ocrTextProvider = ocrTextProvider
    }

    public var pageCount: Int {
        document.pageCount
    }

    // MARK: - BookContentBridge

    public var tableOfContents: [ChapterEntry] {
        get async throws {
            let chapters = segmentByOutline()
            if !chapters.isEmpty {
                return chapters.map { $0.toChapterEntry() }
            }
            return syntheticChapters().map { $0.toChapterEntry() }
        }
    }

    public func extractChapterContent(href: String) async throws -> String {
        guard let range = PDFChapter.parsePageRange(from: href) else {
            return ""
        }
        var texts: [String] = []
        for page in range.startPage...min(range.endPage, pageCount - 1) {
            let text = try await resolvedPageText(page: page)
            if !text.isEmpty {
                texts.append(text)
            }
        }
        return texts.joined(separator: "\n\n")
    }

    public func extractFullText() async throws -> String {
        var texts: [String] = []
        for i in 0..<pageCount {
            let text = try await resolvedPageText(page: i)
            if !text.isEmpty {
                texts.append(text)
            }
        }
        return texts.joined(separator: "\n\n")
    }

    public func searchContent(query: String) async throws -> [ContentSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.isEmpty == false else { return [] }

        var results: [ContentSearchResult] = []

        for pageIndex in 0..<pageCount {
            let text = try await resolvedPageText(page: pageIndex)
            guard text.isEmpty == false else { continue }

            var searchStart = text.startIndex

            while let range = text.range(
                of: normalizedQuery,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<text.endIndex
            ) {
                let snippetStart = text.index(
                    range.lowerBound,
                    offsetBy: -60,
                    limitedBy: text.startIndex
                ) ?? text.startIndex
                let snippetEnd = text.index(
                    range.upperBound,
                    offsetBy: 60,
                    limitedBy: text.endIndex
                ) ?? text.endIndex

                let pageLabel = localizedPageLabel(for: pageIndex)
                results.append(
                    ContentSearchResult(
                        text: String(text[range]),
                        chapterTitle: pageLabel,
                        chapterHref: "pages:\(pageIndex)-\(pageIndex)",
                        textBefore: String(text[snippetStart..<range.lowerBound]),
                        textAfter: String(text[range.upperBound..<snippetEnd]),
                        progression: pageCount > 1
                            ? Double(pageIndex) / Double(pageCount - 1)
                            : 1.0
                    )
                )
                searchStart = range.upperBound
            }
        }
        return results
    }

    // MARK: - Page Text Extraction

    public func extractPageText(page: Int) -> String {
        guard page >= 0 && page < pageCount,
              let pdfPage = document.page(at: page) else { return "" }
        return pdfPage.string ?? ""
    }

    // MARK: - OCR Fallback

    #if canImport(Vision)
    public func ocrPage(page: Int) async throws -> String {
        if let ocrTextProvider {
            return normalizedText(try await ocrTextProvider(page))
        }
        guard page >= 0 && page < pageCount,
              let pdfPage = document.page(at: page) else { return "" }

        let bounds = pdfPage.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return "" }

        ctx.scaleBy(x: scale, y: scale)
        pdfPage.draw(with: .mediaBox, to: ctx)

        guard let cgImage = ctx.makeImage() else { return "" }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = request.results as? [VNRecognizedTextObservation] ?? []
                let text = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #endif

    private func resolvedPageText(page: Int) async throws -> String {
        let nativeText = normalizedText(extractPageText(page: page))
        if nativeText.isEmpty == false {
            return nativeText
        }

        #if canImport(Vision)
        return try await ocrPage(page: page)
        #else
        if let ocrTextProvider {
            return normalizedText(try await ocrTextProvider(page))
        }
        return ""
        #endif
    }

    private func normalizedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Chapter Segmentation

    public func segmentByOutline() -> [PDFChapter] {
        guard let outline = document.outlineRoot else { return [] }
        var chapters: [PDFChapter] = []
        collectOutline(outline, level: 0, into: &chapters)

        for i in 0..<chapters.count {
            let nextStart = (i + 1 < chapters.count) ? chapters[i + 1].startPage : pageCount
            chapters[i] = PDFChapter(
                title: chapters[i].title,
                startPage: chapters[i].startPage,
                endPage: nextStart - 1,
                level: chapters[i].level
            )
        }
        return chapters
    }

    private func collectOutline(_ outline: PDFOutline, level: Int, into chapters: inout [PDFChapter]) {
        for i in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: i) else { continue }
            let title = child.label ?? localizedSectionTitle(for: i)
            let page = child.destination?.page
            let pageIndex = page.flatMap { document.index(for: $0) } ?? 0
            chapters.append(PDFChapter(title: title, startPage: pageIndex, endPage: pageIndex, level: level))
            if child.numberOfChildren > 0 {
                collectOutline(child, level: level + 1, into: &chapters)
            }
        }
    }

    private func syntheticChapters() -> [PDFChapter] {
        guard pageCount > 0 else { return [] }
        let pagesPerChapter = 20
        var chapters: [PDFChapter] = []
        var start = 0
        while start < pageCount {
            let end = min(start + pagesPerChapter - 1, pageCount - 1)
            chapters.append(PDFChapter(
                title: localizedPageRangeTitle(startPage: start, endPage: end),
                startPage: start,
                endPage: end
            ))
            start = end + 1
        }
        return chapters
    }

    private func localizedPageLabel(for pageIndex: Int) -> String {
        if let label = document.page(at: pageIndex)?.label,
           label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return label
        }

        return localizedCatalogFormat("reader.page_number_format", pageIndex + 1)
    }

    private func localizedSectionTitle(for index: Int) -> String {
        localizedCatalogFormat("reader.section_number_format", index + 1)
    }

    private func localizedPageRangeTitle(startPage: Int, endPage: Int) -> String {
        localizedCatalogFormat("reader.pages_range_format", startPage + 1, endPage + 1)
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
#endif
