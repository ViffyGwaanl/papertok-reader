import Foundation
import Observation
import PTCore

@Observable
public final class BookshelfViewModel: @unchecked Sendable {
    public var books: [Book] = []
    public var searchQuery: String = ""
    public var isLoading: Bool = false
    public var isImporting: Bool = false
    public var importError: BookImportError?
    public var sortOrder: SortOrder = .dateDesc

    public enum SortOrder: String, CaseIterable, Sendable {
        case dateDesc, dateAsc, titleAsc, titleDesc, authorAsc
    }

    private let bookDAO: BookDAO
    private let importService: BookImportService

    public init(database: AppDatabase) {
        self.bookDAO = BookDAO(database: database)
        self.importService = BookImportService(database: database)
    }

    public func loadBooks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if searchQuery.isEmpty {
                books = try await bookDAO.fetchAll()
            } else {
                books = try await bookDAO.search(query: searchQuery)
            }
            sortBooks()
        } catch {
            books = []
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
            try await bookDAO.softDelete(id: id)
            books.removeAll { $0.id == id }
        } catch { }
    }

    private func sortBooks() {
        switch sortOrder {
        case .dateDesc: books.sort { $0.createTime > $1.createTime }
        case .dateAsc: books.sort { $0.createTime < $1.createTime }
        case .titleAsc: books.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleDesc: books.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .authorAsc: books.sort { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        }
    }
}
