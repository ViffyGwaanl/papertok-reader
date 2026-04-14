import Foundation
import Testing
@testable import PTFeatures
import PTCore

@Suite("NotesViewModel")
@MainActor
struct NotesViewModelTests {
    @Test("loadNotes resolves book titles and summary")
    func loadNotesResolvesBookTitlesAndSummary() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let noteDAO = BookNoteDAO(database: database)

        let swiftBook = try await bookDAO.save(Book.placeholder(title: "Swift Notes", filePath: "/swift.epub"))
        let aiBook = try await bookDAO.save(Book.placeholder(title: "AI Research", filePath: "/ai.epub"))
        let swiftBookID = try #require(swiftBook.id)
        let aiBookID = try #require(aiBook.id)

        _ = try await noteDAO.save(
            BookNote(
                bookId: swiftBookID,
                content: "Remember protocol extensions",
                cfi: "epubcfi(/6/2)",
                chapter: "Chapter 1",
                type: "highlight",
                color: "#ffff00",
                readerNote: "Tie this to value semantics.",
                createTime: makeDate("2026-04-07"),
                updateTime: makeDate("2026-04-07")
            )
        )
        _ = try await noteDAO.save(
            BookNote(
                bookId: aiBookID,
                content: "Bookmark the evaluation section",
                cfi: "epubcfi(/6/4)",
                chapter: "Results",
                type: "bookmark",
                color: "purple",
                readerNote: nil,
                createTime: makeDate("2026-04-06"),
                updateTime: makeDate("2026-04-06")
            )
        )

        let viewModel = NotesViewModel(database: database)
        await viewModel.loadNotes()

        #expect(viewModel.groupedNotes.count == 2)
        #expect(viewModel.groupedNotes.map(\.bookTitle) == ["Swift Notes", "AI Research"])
        #expect(viewModel.summary.totalNotes == 2)
        #expect(viewModel.summary.booksWithNotes == 2)
    }

    @Test("export renders resolved book titles in markdown and csv")
    func exportRendersResolvedBookTitles() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let noteDAO = BookNoteDAO(database: database)

        let book = try await bookDAO.save(Book.placeholder(title: "Exported Book", filePath: "/export.epub"))
        let bookID = try #require(book.id)
        _ = try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: "Important paragraph",
                cfi: "epubcfi(/6/8)",
                chapter: "Conclusion",
                type: "note",
                color: "green",
                readerNote: "**Follow up** on this argument.",
                createTime: makeDate("2026-04-05"),
                updateTime: makeDate("2026-04-05")
            )
        )

        let viewModel = NotesViewModel(database: database)
        await viewModel.loadNotes()

        let markdown = viewModel.export(format: .markdown)
        #expect(markdown.contains(localizedCatalogString("notes.export.title")))
        #expect(markdown.contains(localizedCatalogFormat("notes.export.total_notes_format", 1)))
        #expect(markdown.contains(localizedCatalogFormat("notes.export.chapter_format", "Conclusion")))
        #expect(markdown.contains(localizedCatalogFormat("notes.export.note_format", "**Follow up** on this argument.")))
        #expect(markdown.contains(localizedCatalogString("common.note")))
        #expect(markdown.contains("Exported Book"))
        #expect(markdown.contains("Important paragraph"))
        #expect(markdown.contains("Follow up"))

        let csv = viewModel.export(format: .csv)
        #expect(csv.contains("book_title,note_type"))
        #expect(csv.contains("Exported Book"))
        #expect(csv.contains("Important paragraph"))

        let text = viewModel.export(format: .txt)
        #expect(text.contains(localizedCatalogString("notes.export.title")))
        #expect(text.contains(localizedCatalogFormat("notes.export.chapter_format", "Conclusion")))
    }

    @Test("filterType filters notes by type")
    func filterTypeFiltersNotes() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let noteDAO = BookNoteDAO(database: database)

        let book = try await bookDAO.save(Book.placeholder(title: "Filter Book", filePath: "/filter.epub"))
        let bookID = try #require(book.id)

        _ = try await noteDAO.save(
            BookNote(bookId: bookID, content: "Highlighted text", cfi: "cfi1", chapter: "Ch1", type: "highlight", color: "yellow", createTime: makeDate("2026-04-07"), updateTime: makeDate("2026-04-07"))
        )
        _ = try await noteDAO.save(
            BookNote(bookId: bookID, content: "Bookmarked page", cfi: "cfi2", chapter: "Ch2", type: "bookmark", color: "blue", createTime: makeDate("2026-04-06"), updateTime: makeDate("2026-04-06"))
        )
        _ = try await noteDAO.save(
            BookNote(bookId: bookID, content: "A note with text", cfi: "cfi3", chapter: "Ch3", type: "note", color: "green", readerNote: "My thoughts", createTime: makeDate("2026-04-05"), updateTime: makeDate("2026-04-05"))
        )

        let viewModel = NotesViewModel(database: database)
        await viewModel.loadNotes()
        #expect(viewModel.notes.count == 3)

        viewModel.filterType = .highlight
        await waitUntil { viewModel.notes.count == 1 }
        #expect(viewModel.notes.count == 1)
        #expect(viewModel.notes.first?.type == "highlight")

        viewModel.filterType = .bookmark
        await waitUntil { viewModel.notes.count == 1 && viewModel.notes.first?.type == "bookmark" }
        #expect(viewModel.notes.count == 1)
        #expect(viewModel.notes.first?.type == "bookmark")

        viewModel.filterType = .all
        await waitUntil { viewModel.notes.count == 3 }
        #expect(viewModel.notes.count == 3)
    }

    @Test("sortOrder sorts notes by chapter")
    func sortOrderSortsByChapter() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let noteDAO = BookNoteDAO(database: database)

        let book = try await bookDAO.save(Book.placeholder(title: "Sort Book", filePath: "/sort.epub"))
        let bookID = try #require(book.id)

        _ = try await noteDAO.save(
            BookNote(bookId: bookID, content: "Note C", cfi: "cfi1", chapter: "Chapter C", type: "highlight", color: "yellow", createTime: makeDate("2026-04-07"), updateTime: makeDate("2026-04-07"))
        )
        _ = try await noteDAO.save(
            BookNote(bookId: bookID, content: "Note A", cfi: "cfi2", chapter: "Chapter A", type: "highlight", color: "yellow", createTime: makeDate("2026-04-06"), updateTime: makeDate("2026-04-06"))
        )

        let viewModel = NotesViewModel(database: database)
        await viewModel.loadNotes()
        viewModel.sortOrder = .chapter

        let chapters = viewModel.groupedNotes.flatMap(\.notes).map(\.chapter)
        #expect(chapters == ["Chapter A", "Chapter C"])
    }

    @Test("missing book titles use localized fallback format")
    func missingBookTitlesUseFallbackFormat() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let noteDAO = BookNoteDAO(database: database)
        let book = try await bookDAO.save(Book.placeholder(title: "Soft Deleted Book", filePath: "/deleted.epub"))
        let bookID = try #require(book.id)

        _ = try await noteDAO.save(
            BookNote(
                bookId: bookID,
                content: "Detached note",
                cfi: "cfi1",
                chapter: "Appendix",
                type: "note",
                color: "green",
                createTime: makeDate("2026-04-07"),
                updateTime: makeDate("2026-04-07")
            )
        )
        try await bookDAO.softDelete(id: bookID)

        let viewModel = NotesViewModel(database: database)
        await viewModel.loadNotes()

        #expect(
            viewModel.groupedNotes.first?.bookTitle
                == localizedCatalogFormat("notes.book_fallback_format", bookID)
        )
    }

    @Test("filter and sort options expose localized display names")
    func filterAndSortDisplayNames() {
        for filter in NotesFilterType.allCases {
            #expect(!filter.displayNameKey.isEmpty)
            #expect(!filter.displayName.isEmpty)
            #expect(!filter.systemImage.isEmpty)
        }

        for sortOrder in NotesSortOrder.allCases {
            #expect(!sortOrder.displayNameKey.isEmpty)
            #expect(!sortOrder.displayName.isEmpty)
        }

        for format in NotesExportFormat.allCases {
            #expect(!format.displayName.isEmpty)
        }
    }

    @Test("updateNote persists changes")
    func updateNotePersistsChanges() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let noteDAO = BookNoteDAO(database: database)

        let book = try await bookDAO.save(Book.placeholder(title: "Edit Book", filePath: "/edit.epub"))
        let bookID = try #require(book.id)

        var note = try await noteDAO.save(
            BookNote(bookId: bookID, content: "Original", cfi: "cfi1", chapter: "Ch1", type: "highlight", color: "yellow", createTime: makeDate("2026-04-07"), updateTime: makeDate("2026-04-07"))
        )

        let viewModel = NotesViewModel(database: database)
        await viewModel.loadNotes()
        #expect(viewModel.notes.first?.readerNote == nil)

        note.readerNote = "Added a note"
        await viewModel.updateNote(note)
        #expect(viewModel.notes.first?.readerNote == "Added a note")
    }

    @Test("note color normalization handles named and hex values")
    func noteColorNormalization() {
        #expect(NoteColorResolver.normalizedHex(for: "yellow") == "E8D890")
        #expect(NoteColorResolver.normalizedHex(for: "#ff00aa") == "FF00AA")
        #expect(NoteColorResolver.normalizedHex(for: "ffd700") == "FFD700")
    }

    private func makeDate(_ raw: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)!
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while condition() == false && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
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
