import Foundation
import Testing
@testable import PTFeatures
import PTCore

@Suite("HighlightExportService")
@MainActor
struct HighlightExportServiceTests {
    @Test("markdown export uses localized summary and section titles")
    func markdownExportUsesLocalizedStrings() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let noteDAO = BookNoteDAO(database: database)

        let book = try await bookDAO.save(Book.placeholder(title: "Localized Export", filePath: "/localized.epub"))
        let bookID = try #require(book.id)

        _ = try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: "Important quote",
                cfi: "epubcfi(/6/2)",
                chapter: "Intro",
                type: "highlight",
                color: "yellow",
                readerNote: "Remember this",
                createTime: makeDate("2026-04-05"),
                updateTime: makeDate("2026-04-05")
            )
        )

        let output = try await HighlightExportService().export(
            bookId: bookID,
            bookTitle: "Localized Export",
            format: .markdown,
            database: database
        )

        #expect(output.contains("Localized Export"))
        #expect(output.contains(localizedCatalogString("reader.export.group_highlights")))
        #expect(output.contains("Important quote"))
    }

    @Test("plain text export uses localized labels")
    func plainTextExportUsesLocalizedLabels() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let noteDAO = BookNoteDAO(database: database)

        let book = try await bookDAO.save(Book.placeholder(title: "Plain Export", filePath: "/plain.epub"))
        let bookID = try #require(book.id)

        _ = try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: "Bookmark this",
                cfi: "epubcfi(/6/4)",
                chapter: "Chapter 2",
                type: "bookmark",
                color: "blue",
                readerNote: "Use later",
                createTime: makeDate("2026-04-06"),
                updateTime: makeDate("2026-04-06")
            )
        )

        let output = try await HighlightExportService().export(
            bookId: bookID,
            bookTitle: "Plain Export",
            format: .plaintext,
            database: database
        )

        #expect(output.contains(localizedCatalogString("reader.bookmark")))
        #expect(output.contains(localizedCatalogFormat("reader.export.chapter_format", "Chapter 2")))
        #expect(output.contains(localizedCatalogFormat("reader.export.note_format", "Use later")))
    }

    private func makeDate(_ raw: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)!
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
