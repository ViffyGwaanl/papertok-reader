import Testing
import Foundation
@testable import PTFeatures
import PTAIServices
import PTCore

@MainActor
@Suite("ConversationListViewModel")
struct ConversationListViewModelTests {

    // MARK: - Test Fixtures

    private static func makeTempService() -> (ConversationPersistenceService, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConvListVMTest-\(UUID().uuidString)")
        let defaults = UserDefaults(suiteName: "ConvListVMTest-\(UUID().uuidString)")!
        let service = ConversationPersistenceService(directory: dir, userDefaults: defaults)
        return (service, dir)
    }

    private static func persist(
        _ service: ConversationPersistenceService,
        id: String = UUID().uuidString,
        title: String,
        lastUserText: String = "body",
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        isPinned: Bool = false,
        bookId: String? = nil
    ) throws -> String {
        var tree = ConversationTree(systemPrompt: "s")
        tree.append(ChatMessage(role: .user, content: [.text(lastUserText)]))
        let p = ConversationPersistenceService.PersistedConversation(
            id: id,
            title: title,
            systemPrompt: "s",
            tree: tree,
            createdAt: createdAt,
            updatedAt: updatedAt,
            providerId: nil,
            modelId: nil,
            isPinned: isPinned,
            bookId: bookId
        )
        try service.save(p)
        return id
    }

    private static func makeChatVM() -> AIChatViewModel {
        AIChatViewModel()
    }

    // MARK: - Search

    @Test("search filters by title")
    func searchFiltersByTitle() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try Self.persist(service, title: "Alpha notes")
        _ = try Self.persist(service, title: "Beta plans")
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        vm.setSearchQuery("alpha")
        #expect(vm.conversations.count == 1)
        #expect(vm.conversations.first?.title == "Alpha notes")
    }

    @Test("search filters by snippet")
    func searchFiltersBySnippet() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try Self.persist(service, title: "Conv one", lastUserText: "hello world")
        _ = try Self.persist(service, title: "Conv two", lastUserText: "goodbye")
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        vm.setSearchQuery("goodbye")
        #expect(vm.conversations.count == 1)
        #expect(vm.conversations.first?.title == "Conv two")
    }

    @Test("search is case-insensitive")
    func searchIsCaseInsensitive() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try Self.persist(service, title: "MyTitle")
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        vm.setSearchQuery("MYTITLE")
        #expect(vm.conversations.count == 1)
    }

    // MARK: - Book filter

    @Test("book filter .all shows everything")
    func bookFilterAllShowsEverything() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try Self.persist(service, title: "A", bookId: "book-1")
        _ = try Self.persist(service, title: "B", bookId: nil)
        _ = try Self.persist(service, title: "C", bookId: "book-2")
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        vm.setBookFilter(.all)
        #expect(vm.conversations.count == 3)
    }

    @Test("book filter .global shows only nil bookId")
    func bookFilterGlobalShowsOnlyNilBookId() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try Self.persist(service, title: "A", bookId: "book-1")
        _ = try Self.persist(service, title: "B", bookId: nil)
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        vm.setBookFilter(.global)
        #expect(vm.conversations.count == 1)
        #expect(vm.conversations.first?.title == "B")
    }

    @Test("book filter .book shows only matching")
    func bookFilterByBookShowsOnlyMatching() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try Self.persist(service, title: "A", bookId: "book-1")
        _ = try Self.persist(service, title: "B", bookId: "book-2")
        _ = try Self.persist(service, title: "C", bookId: nil)
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        vm.setBookFilter(.book(id: "book-1"))
        #expect(vm.conversations.count == 1)
        #expect(vm.conversations.first?.title == "A")
    }

    // MARK: - Pinned clustering

    @Test("pinnedFirst clusters pinned conversations at top")
    func pinnedFirstClustersTop() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try Self.persist(service, title: "Old pinned", updatedAt: t0, isPinned: true)
        _ = try Self.persist(service, title: "Newest", updatedAt: t0.addingTimeInterval(1000), isPinned: false)
        _ = try Self.persist(service, title: "Middle", updatedAt: t0.addingTimeInterval(500), isPinned: false)
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        #expect(vm.conversations.first?.title == "Old pinned")
        #expect(vm.conversations.first?.isPinned == true)
        let unpinned = vm.conversations.dropFirst().map(\.title)
        #expect(unpinned == ["Newest", "Middle"])
    }

    @Test("togglePin updates persistence and ordering")
    func togglePinUpdatesPersistenceAndOrdering() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let idA = try Self.persist(service, title: "A", updatedAt: t0)
        _ = try Self.persist(service, title: "B", updatedAt: t0.addingTimeInterval(1000))
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        #expect(vm.conversations.first?.title == "B")
        try await vm.togglePin(id: idA)
        #expect(vm.conversations.first?.title == "A")
        #expect(vm.conversations.first?.isPinned == true)
        let reloaded = try #require(try service.load(id: idA))
        #expect(reloaded.isPinned == true)
    }

    // MARK: - Rename

    @Test("rename updates title and updatedAt")
    func renameUpdatesTitleAndUpdatedAt() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let id = try Self.persist(service, title: "Old", updatedAt: t0)
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        try await vm.rename(id: id, to: "  New Title  ")
        let reloaded = try #require(try service.load(id: id))
        #expect(reloaded.title == "New Title")
        #expect(reloaded.updatedAt > t0)
    }

    @Test("rename with empty string throws")
    func renameWithEmptyStringThrows() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try Self.persist(service, title: "Old")
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        await #expect(throws: ConversationListError.self) {
            try await vm.rename(id: id, to: "   ")
        }
    }

    // MARK: - Delete

    @Test("delete removes conversation from persistence")
    func deleteRemovesFromPersistence() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try Self.persist(service, title: "Gone")
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        try await vm.delete(id: id)
        #expect(vm.conversations.isEmpty)
        #expect((try service.load(id: id)) == nil)
    }

    // MARK: - Export

    @Test("export markdown produces expected file")
    func exportMarkdownProducesExpectedFile() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try Self.persist(service, title: "Exportable", lastUserText: "Hello there")
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        let url = try await vm.export(id: id, format: .markdown)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let content = try String(contentsOf: url)
        #expect(content.contains("# Exportable"))
        #expect(content.contains("Hello there"))
        #expect(url.pathExtension == "md")
    }

    @Test("export JSON produces valid round-trippable JSON")
    func exportJSONProducesValidJSON() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = try Self.persist(service, title: "JSONable", isPinned: false, bookId: "book-xyz")
        // mark pinned after save via persistence
        if var loaded = try service.load(id: id) {
            loaded.isPinned = true
            try service.save(loaded)
        }
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        await vm.refresh()
        let url = try await vm.export(id: id, format: .json)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension == "json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ConversationPersistenceService.PersistedConversation.self, from: data)
        #expect(decoded.title == "JSONable")
        #expect(decoded.bookId == "book-xyz")
        #expect(decoded.isPinned == true)
    }

    // MARK: - Sorting

    @Test("sort by lastUsed / created / title")
    func sortModes() async throws {
        let (service, dir) = Self.makeTempService()
        defer { try? FileManager.default.removeItem(at: dir) }
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try Self.persist(service, title: "Banana", createdAt: t0.addingTimeInterval(10), updatedAt: t0.addingTimeInterval(30))
        _ = try Self.persist(service, title: "Apple", createdAt: t0.addingTimeInterval(20), updatedAt: t0.addingTimeInterval(10))
        _ = try Self.persist(service, title: "Cherry", createdAt: t0.addingTimeInterval(5), updatedAt: t0.addingTimeInterval(20))
        let vm = ConversationListViewModel(persistence: service, chatViewModel: Self.makeChatVM())
        vm.pinnedFirst = false
        await vm.refresh()

        vm.setSortMode(.lastUsed)
        #expect(vm.conversations.map(\.title) == ["Banana", "Cherry", "Apple"])

        vm.setSortMode(.created)
        #expect(vm.conversations.map(\.title) == ["Apple", "Banana", "Cherry"])

        vm.setSortMode(.title)
        #expect(vm.conversations.map(\.title) == ["Apple", "Banana", "Cherry"])
    }
}
