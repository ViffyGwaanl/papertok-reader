import Foundation
import Observation
import PTCore

public enum BookshelfEditError: LocalizedError, Sendable {
    case emptyTitle
    case bookNotFound

    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            localizedCatalogString("bookshelf.edit.empty_title_required")
        case .bookNotFound:
            localizedCatalogString("bookshelf.edit.book_not_found")
        }
    }
}

@MainActor @Observable
public final class BookshelfViewModel {
    public var books: [Book] = []
    public var tags: [Tag] = []
    public var groups: [TbGroup] = []
    public var searchQuery: String = ""
    public var isLoading: Bool = false
    public var isImporting: Bool = false
    public var importError: BookImportError?
    public var pendingUndoBook: Book?
    public var selectedStatusFilters: Set<ReadingStatusFilter> = []
    public var selectedTagIDs: Set<Int64> = []
    public var includeNoTagFilter = false
    public var sortOrder: SortOrder {
        didSet { persistSortOrder() }
    }
    public private(set) var bookTagIDs: [Int64: Set<Int64>] = [:]

    // MARK: - Edit mode (multi-select & batch)

    public var isEditMode: Bool = false
    public var selectedBookIDs: Set<Int64> = []

    public enum SortOrder: String, CaseIterable, Sendable {
        case dateDesc, dateAsc, titleAsc, titleDesc, authorAsc
    }

    public enum ReadingStatusFilter: String, CaseIterable, Hashable, Sendable {
        case finished
        case reading
        case notStarted

        public var title: String {
            switch self {
            case .finished:
                localizedCatalogString("bookshelf.completed")
            case .reading:
                localizedCatalogString("bookshelf.in_progress")
            case .notStarted:
                localizedCatalogString("bookshelf.unread")
            }
        }
    }

    private let bookDAO: BookDAO
    private let tagDAO: TagDAO
    private let groupDAO: GroupDAO
    private let importService: BookImportService
    private let userDefaults: UserDefaults

    private static let sortOrderKey = "bookshelf.sortOrder"

    public init(database: AppDatabase, userDefaults: UserDefaults = .standard) {
        self.bookDAO = BookDAO(database: database)
        self.tagDAO = TagDAO(database: database)
        self.groupDAO = GroupDAO(database: database)
        self.importService = BookImportService(database: database)
        self.userDefaults = userDefaults
        if let raw = userDefaults.string(forKey: Self.sortOrderKey),
           let restored = SortOrder(rawValue: raw) {
            self.sortOrder = restored
        } else {
            self.sortOrder = .dateDesc
        }
    }

    public func loadBooks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let baseBooks: [Book]
            if searchQuery.isEmpty {
                baseBooks = try await bookDAO.fetchAll()
            } else {
                baseBooks = try await bookDAO.search(query: searchQuery)
            }

            let tagIDsByBookID = try await loadBookTagIDs(for: baseBooks)
            bookTagIDs = tagIDsByBookID

            books = applyTagFilters(
                to: applyStatusFilters(to: baseBooks),
                tagIDsByBookID: tagIDsByBookID
            )
            sortBooks()
        } catch {
            books = []
            bookTagIDs = [:]
        }
    }

    public func loadTags() async {
        do {
            tags = try await tagDAO.fetchAll()
        } catch {
            tags = []
        }
    }

    public func loadGroups() async {
        do {
            groups = try await groupDAO.fetchAll()
        } catch {
            groups = []
        }
    }

    /// Import a book file from the given URL. On success, prepends the new book to `books`.
    public func importBook(url: URL) async {
        isImporting = true
        importError = nil
        defer { isImporting = false }
        do {
            let book = try await importService.importFile(from: url)
            books.insert(book, at: 0)
        } catch let error as BookImportError {
            importError = error
        } catch {
            importError = .saveFailed(error)
        }
    }

    public func deleteBook(id: Int64) async {
        do {
            pendingUndoBook = try await bookDAO.fetchById(id)
            try await bookDAO.softDelete(id: id)
            books.removeAll { $0.id == id }
        } catch { }
    }

    public func undoLastDelete() async {
        guard let book = pendingUndoBook,
              let id = book.id else { return }

        do {
            try await bookDAO.restore(id: id)
            pendingUndoBook = nil
            await loadBooks()
        } catch { }
    }

    public func clearPendingUndo() {
        pendingUndoBook = nil
    }

    public func updateBookMetadata(id: Int64, title: String, author: String) async throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTitle.isEmpty == false else {
            throw BookshelfEditError.emptyTitle
        }

        guard var book = try await bookDAO.fetchById(id) else {
            throw BookshelfEditError.bookNotFound
        }

        book.title = normalizedTitle
        book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        book.updateTime = Date()
        _ = try await bookDAO.save(book)
        await loadBooks()
    }

    public func toggleStatusFilter(_ filter: ReadingStatusFilter) {
        if selectedStatusFilters.contains(filter) {
            selectedStatusFilters.remove(filter)
        } else {
            selectedStatusFilters.insert(filter)
        }
    }

    public func toggleTagFilter(_ tagId: Int64) {
        if selectedTagIDs.contains(tagId) {
            selectedTagIDs.remove(tagId)
        } else {
            selectedTagIDs.insert(tagId)
        }
    }

    public func toggleNoTagFilter() {
        includeNoTagFilter.toggle()
    }

    public func tagIDs(forBookId bookId: Int64) -> Set<Int64> {
        bookTagIDs[bookId] ?? []
    }

    public var rootGroups: [TbGroup] {
        groups.filter { ($0.parentId ?? 0) == 0 }
    }

    public func childGroups(of parentId: Int64) -> [TbGroup] {
        groups.filter { $0.parentId == parentId }
    }

    @discardableResult
    public func createTag(name: String, colorHex: String?) async throws -> Tag {
        let tag = try await tagDAO.create(name: name, colorHex: normalizedColorHex(colorHex))
        await loadTags()
        return tag
    }

    @discardableResult
    public func updateTag(id: Int64, name: String, colorHex: String?) async throws -> Tag {
        let tag = try await tagDAO.update(id: id, name: name, colorHex: normalizedColorHex(colorHex))
        await loadTags()
        return tag
    }

    public func deleteTag(id: Int64) async throws {
        try await tagDAO.delete(id: id)
        selectedTagIDs.remove(id)
        await loadTags()
        await loadBooks()
    }

    public func assignTag(tagId: Int64, toBookId bookId: Int64) async throws {
        try await tagDAO.attachTag(tagId: tagId, toBookId: bookId)
        await loadBooks()
    }

    public func detachTag(tagId: Int64, fromBookId bookId: Int64) async throws {
        try await tagDAO.detachTag(tagId: tagId, fromBookId: bookId)
        await loadBooks()
    }

    @discardableResult
    public func createGroup(name: String, parentId: Int64? = nil) async throws -> TbGroup {
        let group = try await groupDAO.create(name: name, parentId: parentId)
        await loadGroups()
        return group
    }

    @discardableResult
    public func renameGroup(id: Int64, to name: String) async throws -> TbGroup {
        let group = try await groupDAO.rename(id: id, to: name)
        await loadGroups()
        return group
    }

    public func deleteGroup(id: Int64) async throws {
        let parentId = try await groupDAO.fetchById(id)?.parentId
        try await bookDAO.moveBooks(inGroupId: id, toGroupId: parentId)
        try await groupDAO.reparentChildren(fromParentId: id, toParentId: parentId)
        try await groupDAO.softDelete(id: id)
        await loadGroups()
        await loadBooks()
    }

    public func moveBook(id: Int64, toGroupId groupId: Int64?) async throws {
        try await bookDAO.move(id: id, toGroupId: groupId)
        if let index = books.firstIndex(where: { $0.id == id }) {
            books[index].groupId = groupId ?? 0
        }
    }

    public func dissolveGroup(id: Int64) async throws {
        let parentId = try await groupDAO.fetchById(id)?.parentId
        try await bookDAO.moveBooks(inGroupId: id, toGroupId: parentId)
        try await groupDAO.reparentChildren(fromParentId: id, toParentId: parentId)
        try await groupDAO.softDelete(id: id)
        await loadGroups()
        await loadBooks()
    }

    private func sortBooks() {
        switch sortOrder {
        case .dateDesc: books.sort { $0.createTime > $1.createTime }
        case .dateAsc: books.sort { $0.createTime < $1.createTime }
        case .titleAsc:
            books.sort { LocalizedSort.isAscending($0.title, $1.title) }
        case .titleDesc:
            books.sort { LocalizedSort.compare($0.title, $1.title) == .orderedDescending }
        case .authorAsc:
            books.sort { LocalizedSort.isAscending($0.author, $1.author) }
        }
    }

    private func applyStatusFilters(to books: [Book]) -> [Book] {
        guard selectedStatusFilters.isEmpty == false else { return books }
        return books.filter(matchesSelectedStatusFilters)
    }

    private func applyTagFilters(
        to books: [Book],
        tagIDsByBookID: [Int64: Set<Int64>]
    ) -> [Book] {
        guard selectedTagIDs.isEmpty == false || includeNoTagFilter else {
            return books
        }

        return books.filter { book in
            guard let bookId = book.id else { return false }
            let tagIDs = tagIDsByBookID[bookId] ?? []
            let matchesSelectedTags = selectedTagIDs.isEmpty == false && tagIDs.isDisjoint(with: selectedTagIDs) == false
            let matchesNoTag = includeNoTagFilter && tagIDs.isEmpty
            return matchesSelectedTags || matchesNoTag
        }
    }

    private func loadBookTagIDs(for books: [Book]) async throws -> [Int64: Set<Int64>] {
        var result: [Int64: Set<Int64>] = [:]
        for book in books {
            guard let bookId = book.id else { continue }
            let tagIDs = try await tagDAO.fetchTagIds(forBookId: bookId)
            result[bookId] = Set(tagIDs)
        }
        return result
    }

    private func matchesSelectedStatusFilters(_ book: Book) -> Bool {
        let progress = book.readingPercentage
        let status: ReadingStatusFilter
        if progress >= 0.999 {
            status = .finished
        } else if progress <= 0.001 {
            status = .notStarted
        } else {
            status = .reading
        }
        return selectedStatusFilters.contains(status)
    }

    // MARK: - Batch operations (edit mode)

    public func toggleEditMode() {
        isEditMode.toggle()
        if !isEditMode {
            selectedBookIDs.removeAll()
        }
    }

    public func toggleBookSelection(_ bookId: Int64) {
        if selectedBookIDs.contains(bookId) {
            selectedBookIDs.remove(bookId)
        } else {
            selectedBookIDs.insert(bookId)
        }
    }

    public func selectAllBooks() {
        selectedBookIDs = Set(books.compactMap(\.id))
    }

    public func batchDeleteSelectedBooks() async {
        for bookId in selectedBookIDs {
            try? await bookDAO.softDelete(id: bookId)
        }
        books.removeAll { selectedBookIDs.contains($0.id ?? -1) }
        selectedBookIDs.removeAll()
    }

    public func batchMoveSelectedBooks(toGroupId groupId: Int64?) async {
        for bookId in selectedBookIDs {
            try? await bookDAO.move(id: bookId, toGroupId: groupId)
        }
        selectedBookIDs.removeAll()
        await loadBooks()
    }

    private func persistSortOrder() {
        userDefaults.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
    }

    private func normalizedColorHex(_ colorHex: String?) -> String? {
        guard let colorHex else {
            return nil
        }
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func localizedCatalogString(_ key: String, locale: Locale = .autoupdatingCurrent) -> String {
    String(localized: String.LocalizationValue(key), bundle: localizedCatalogBundle(), locale: locale)
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
