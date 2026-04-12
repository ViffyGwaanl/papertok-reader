import Testing
import Foundation
import PDFKit
@testable import PTFeatures

@Suite("BookshelfViewModel")
@MainActor
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
        #expect(vm.pendingUndoBook?.id == book.id)
    }

    @Test("Undo restore brings a soft-deleted book back")
    func undoDelete() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)
        let book = try await dao.save(Book.placeholder(title: "Restore Me", filePath: "/restore.epub"))

        let vm = BookshelfViewModel(database: db)
        await vm.loadBooks()
        await vm.deleteBook(id: book.id!)
        #expect(vm.books.isEmpty)
        #expect(vm.pendingUndoBook?.id == book.id)

        await vm.undoLastDelete()

        #expect(vm.pendingUndoBook == nil)
        #expect(vm.books.count == 1)
        #expect(vm.books.first?.title == "Restore Me")
    }

    @Test("Import adds book to list")
    func importBook() async throws {
        let db = try AppDatabase.makeInMemory()
        let vm = BookshelfViewModel(database: db)

        // Create a minimal one-page PDF in temp directory
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_import_\(UUID().uuidString).pdf")
        let pdfDoc = PDFDocument()
        pdfDoc.insert(PDFPage(), at: 0)
        guard let data = pdfDoc.dataRepresentation() else {
            Issue.record("Could not create test PDF")
            return
        }
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await vm.importBook(url: tempURL)

        #expect(vm.importError == nil, "Expected no error but got \(String(describing: vm.importError))")
        #expect(vm.books.count == 1)
        #expect(vm.books.first?.filePath.hasSuffix(".pdf") == true)
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

    @Test("Editing book metadata persists updated title and author")
    func editBookMetadata() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)
        var draft = Book.placeholder(title: "Draft Title", filePath: "/draft.epub")
        draft.author = "Anon"
        let book = try await dao.save(draft)
        let bookID = try #require(book.id)

        let vm = BookshelfViewModel(database: db)
        try await vm.updateBookMetadata(id: bookID, title: "Published Title", author: "PaperTok")

        let persisted = try #require(await dao.fetchById(bookID))
        #expect(persisted.title == "Published Title")
        #expect(persisted.author == "PaperTok")

        await vm.loadBooks()
        #expect(vm.books.first?.title == "Published Title")
        #expect(vm.books.first?.author == "PaperTok")
    }

    @Test("Reading status filters combine correctly")
    func readingStatusFilters() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)

        var unread = Book.placeholder(title: "Unread", filePath: "/u.epub")
        unread.readingPercentage = 0
        _ = try await dao.save(unread)

        var reading = Book.placeholder(title: "Reading", filePath: "/r.epub")
        reading.readingPercentage = 0.45
        _ = try await dao.save(reading)

        var finished = Book.placeholder(title: "Finished", filePath: "/f.epub")
        finished.readingPercentage = 1
        _ = try await dao.save(finished)

        let vm = BookshelfViewModel(database: db)
        vm.selectedStatusFilters = [.notStarted, .reading]
        await vm.loadBooks()

        #expect(vm.books.count == 2)
        #expect(vm.books.map(\.title).contains("Unread"))
        #expect(vm.books.map(\.title).contains("Reading"))
        #expect(vm.books.map(\.title).contains("Finished") == false)
    }

    @Test("Tag CRUD, assignment, and no-tag filtering work through the view model")
    func tagCrudAndFiltering() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)
        let taggedBook = try await dao.save(Book.placeholder(title: "Tagged", filePath: "/tagged.epub"))
        _ = try await dao.save(Book.placeholder(title: "Untagged", filePath: "/untagged.epub"))

        let vm = BookshelfViewModel(database: db)
        let createdTag = try await vm.createTag(name: "AI", colorHex: "#ff0000")
        let createdTagID = try #require(createdTag.id)
        let taggedBookID = try #require(taggedBook.id)
        #expect(createdTag.name == "AI")
        #expect(createdTag.colorHex == "#ff0000")

        let updatedTag = try await vm.updateTag(id: createdTagID, name: "ML", colorHex: "#00ff00")
        let updatedTagID = try #require(updatedTag.id)
        #expect(updatedTag.name == "ML")
        #expect(updatedTag.colorHex == "#00ff00")

        try await vm.assignTag(tagId: updatedTagID, toBookId: taggedBookID)
        await vm.loadBooks()
        #expect(vm.tagIDs(forBookId: taggedBookID).contains(updatedTagID))

        vm.selectedTagIDs = [updatedTagID]
        vm.includeNoTagFilter = false
        await vm.loadBooks()
        #expect(vm.books.map(\.title) == ["Tagged"])

        vm.selectedTagIDs = []
        vm.includeNoTagFilter = true
        await vm.loadBooks()
        #expect(vm.books.map(\.title) == ["Untagged"])

        try await vm.deleteTag(id: updatedTagID)
        await vm.loadTags()
        #expect(vm.tags.isEmpty)

        await vm.loadBooks()
        #expect(Set(vm.books.map(\.title)) == Set(["Tagged", "Untagged"]))
    }

    @Test("Group hierarchy, rename, move, and dissolve update persisted state")
    func groupsHierarchyMoveAndDissolve() async throws {
        let db = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: db)
        let book = try await bookDAO.save(Book.placeholder(title: "Grouped", filePath: "/grouped.epub"))

        let vm = BookshelfViewModel(database: db)
        let parent = try await vm.createGroup(name: "Parent")
        let parentID = try #require(parent.id)
        let bookID = try #require(book.id)
        let child = try await vm.createGroup(name: "Child", parentId: parentID)
        let childID = try #require(child.id)

        await vm.loadGroups()
        #expect(vm.rootGroups.map(\.name) == ["Parent"])
        #expect(vm.childGroups(of: parentID).map(\.name) == ["Child"])

        let renamedChild = try await vm.renameGroup(id: childID, to: "Renamed Child")
        #expect(renamedChild.name == "Renamed Child")

        try await vm.moveBook(id: bookID, toGroupId: parentID)
        let movedBook = try #require(await bookDAO.fetchById(bookID))
        #expect(movedBook.groupId == parentID)

        try await vm.dissolveGroup(id: parentID)
        await vm.loadGroups()

        let dissolvedBook = try #require(await bookDAO.fetchById(bookID))
        #expect(dissolvedBook.groupId == 0)
        #expect(vm.rootGroups.map(\.name).contains("Parent") == false)
        #expect(vm.rootGroups.map(\.name).contains("Renamed Child"))
    }

    @Test("Deleting a group hides it from the loaded hierarchy")
    func deleteGroup() async throws {
        let db = try AppDatabase.makeInMemory()
        let vm = BookshelfViewModel(database: db)

        let group = try await vm.createGroup(name: "Archive")
        let groupID = try #require(group.id)
        await vm.loadGroups()
        #expect(vm.rootGroups.map(\.name) == ["Archive"])

        try await vm.deleteGroup(id: groupID)
        await vm.loadGroups()
        #expect(vm.groups.isEmpty)
    }

    @Test("Sort order persists to UserDefaults and restores on init")
    func sortOrderPersistence() async throws {
        let db = try AppDatabase.makeInMemory()
        let suiteName = "test-sort-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let vm1 = BookshelfViewModel(database: db, userDefaults: defaults)
        #expect(vm1.sortOrder == .dateDesc) // default

        vm1.sortOrder = .titleAsc
        #expect(defaults.string(forKey: "bookshelf.sortOrder") == "titleAsc")

        let vm2 = BookshelfViewModel(database: db, userDefaults: defaults)
        #expect(vm2.sortOrder == .titleAsc)
    }

    @Test("Edit mode toggle and selection")
    func editModeToggle() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)
        let bookA = try await dao.save(Book.placeholder(title: "A", filePath: "/a.epub"))
        let bookB = try await dao.save(Book.placeholder(title: "B", filePath: "/b.epub"))

        let vm = BookshelfViewModel(database: db)
        await vm.loadBooks()
        #expect(vm.isEditMode == false)

        vm.toggleEditMode()
        #expect(vm.isEditMode == true)

        vm.toggleBookSelection(bookA.id!)
        vm.toggleBookSelection(bookB.id!)
        #expect(vm.selectedBookIDs.count == 2)

        // Deselect one
        vm.toggleBookSelection(bookA.id!)
        #expect(vm.selectedBookIDs == [bookB.id!])

        // Toggle edit mode off clears selection
        vm.toggleEditMode()
        #expect(vm.isEditMode == false)
        #expect(vm.selectedBookIDs.isEmpty)
    }

    @Test("Select all selects every visible book")
    func selectAll() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)
        _ = try await dao.save(Book.placeholder(title: "A", filePath: "/a.epub"))
        _ = try await dao.save(Book.placeholder(title: "B", filePath: "/b.epub"))
        _ = try await dao.save(Book.placeholder(title: "C", filePath: "/c.epub"))

        let vm = BookshelfViewModel(database: db)
        await vm.loadBooks()
        vm.selectAllBooks()
        #expect(vm.selectedBookIDs.count == 3)
    }

    @Test("Batch delete removes selected books")
    func batchDelete() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)
        let bookA = try await dao.save(Book.placeholder(title: "A", filePath: "/a.epub"))
        let bookB = try await dao.save(Book.placeholder(title: "B", filePath: "/b.epub"))
        _ = try await dao.save(Book.placeholder(title: "C", filePath: "/c.epub"))

        let vm = BookshelfViewModel(database: db)
        await vm.loadBooks()
        #expect(vm.books.count == 3)

        vm.selectedBookIDs = [bookA.id!, bookB.id!]
        await vm.batchDeleteSelectedBooks()

        #expect(vm.books.count == 1)
        #expect(vm.books.first?.title == "C")
        #expect(vm.selectedBookIDs.isEmpty)
    }

    @Test("Batch move moves selected books to target group")
    func batchMove() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookDAO(database: db)
        let bookA = try await dao.save(Book.placeholder(title: "A", filePath: "/a.epub"))
        let bookB = try await dao.save(Book.placeholder(title: "B", filePath: "/b.epub"))

        let vm = BookshelfViewModel(database: db)
        let group = try await vm.createGroup(name: "Target")
        let groupID = try #require(group.id)
        await vm.loadBooks()

        vm.selectedBookIDs = [bookA.id!, bookB.id!]
        await vm.batchMoveSelectedBooks(toGroupId: groupID)

        let movedA = try #require(await dao.fetchById(bookA.id!))
        let movedB = try #require(await dao.fetchById(bookB.id!))
        #expect(movedA.groupId == groupID)
        #expect(movedB.groupId == groupID)
        #expect(vm.selectedBookIDs.isEmpty)
    }
}
