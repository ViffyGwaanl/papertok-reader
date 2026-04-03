import Testing
import Foundation
@testable import PTFeatures

@Suite("BookshelfViewModel")
struct BookshelfViewModelTests {
    @Test("Loads books from database")
    func loadBooks() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)
        _ = try await dao.save(Book.placeholder(title: "Book A", filePath: "/a.epub"))
        _ = try await dao.save(Book.placeholder(title: "Book B", filePath: "/b.epub"))

        let vm = BookshelfViewModel(database: db)
        await vm.loadBooks()
        #expect(vm.books.count == 2)
    }

    @Test("Search filters books")
    func searchBooks() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)
        _ = try await dao.save(Book.placeholder(title: "Swift Programming", filePath: "/a.epub"))
        _ = try await dao.save(Book.placeholder(title: "Rust Handbook", filePath: "/b.epub"))

        let vm = BookshelfViewModel(database: db)
        vm.searchQuery = "Swift"
        await vm.loadBooks()
        #expect(vm.books.count == 1)
        #expect(vm.books[0].title == "Swift Programming")
    }

    @Test("Soft delete removes book from list")
    func deleteBook() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)
        let book = try await dao.save(Book.placeholder(title: "Delete Me", filePath: "/del.epub"))

        let vm = BookshelfViewModel(database: db)
        await vm.loadBooks()
        #expect(vm.books.count == 1)

        await vm.deleteBook(id: book.id!)
        #expect(vm.books.count == 0)
    }

    @Test("Sort order changes book ordering")
    func sortOrder() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)
        _ = try await dao.save(Book.placeholder(title: "Zebra", filePath: "/z.epub"))
        _ = try await dao.save(Book.placeholder(title: "Apple", filePath: "/a.epub"))

        let vm = BookshelfViewModel(database: db)
        vm.sortOrder = .titleAsc
        await vm.loadBooks()
        #expect(vm.books[0].title == "Apple")
        #expect(vm.books[1].title == "Zebra")
    }
}
