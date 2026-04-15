import Foundation
import Testing
@testable import PTAIServices
@testable import PTCore
@testable import PTFeatures

@MainActor
@Suite("MCPServerDetailViewModel")
struct MCPServerDetailViewModelTests {
    @Test("loadNewServerStartsWithBlankTemplate")
    func loadNewServerStartsWithBlankTemplate() async throws {
        let fixture = try makeFixture()
        let vm = MCPServerDetailViewModel(store: fixture.store, client: StubToolsClient())
        await vm.load(serverId: nil)
        #expect(vm.isNew)
        #expect(vm.draft.name == "")
        #expect(vm.draft.transportType == .httpSSE)
        #expect(vm.draft.isEnabled)
    }

    @Test("loadExistingServerPopulatesDraft")
    func loadExistingServerPopulatesDraft() async throws {
        let fixture = try makeFixture()
        let seed = MCPServerConfig(id: "abc", name: "Local", url: "https://example.com")
        try await fixture.store.add(seed)

        let vm = MCPServerDetailViewModel(store: fixture.store, client: StubToolsClient())
        await vm.load(serverId: "abc")
        #expect(!vm.isNew)
        #expect(vm.draft.id == "abc")
        #expect(vm.draft.name == "Local")
    }

    @Test("saveNewServerCallsStoreAdd")
    func saveNewServerCallsStoreAdd() async throws {
        let fixture = try makeFixture()
        let vm = MCPServerDetailViewModel(store: fixture.store, client: StubToolsClient())
        await vm.load(serverId: nil)
        vm.updateName("My Server")
        vm.updateURL("https://example.com")
        try await vm.save()

        let loaded = await fixture.store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "My Server")
        #expect(!vm.isNew)
    }

    @Test("saveExistingServerCallsStoreUpdate")
    func saveExistingServerCallsStoreUpdate() async throws {
        let fixture = try makeFixture()
        let seed = MCPServerConfig(id: "abc", name: "Old", url: "https://example.com")
        try await fixture.store.add(seed)

        let vm = MCPServerDetailViewModel(store: fixture.store, client: StubToolsClient())
        await vm.load(serverId: "abc")
        vm.updateName("Renamed")
        try await vm.save()

        let loaded = await fixture.store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "Renamed")
    }

    @Test("saveRejectsEmptyName")
    func saveRejectsEmptyName() async throws {
        let fixture = try makeFixture()
        let vm = MCPServerDetailViewModel(store: fixture.store, client: StubToolsClient())
        await vm.load(serverId: nil)
        vm.updateURL("https://example.com")
        await #expect(throws: MCPServerDetailViewModel.SaveError.invalidName) {
            try await vm.save()
        }
        #expect(vm.connectionError != nil)
    }

    @Test("saveRejectsEmptyURLForHTTPSSE")
    func saveRejectsEmptyURLForHTTPSSE() async throws {
        let fixture = try makeFixture()
        let vm = MCPServerDetailViewModel(store: fixture.store, client: StubToolsClient())
        await vm.load(serverId: nil)
        vm.updateName("Named")
        await #expect(throws: MCPServerDetailViewModel.SaveError.invalidURL) {
            try await vm.save()
        }
    }

    @Test("saveRejectsEmptyCommandForStdio")
    func saveRejectsEmptyCommandForStdio() async throws {
        let fixture = try makeFixture()
        let vm = MCPServerDetailViewModel(store: fixture.store, client: StubToolsClient())
        await vm.load(serverId: nil)
        vm.updateName("Named")
        vm.updateTransport(.stdio)
        await #expect(throws: MCPServerDetailViewModel.SaveError.invalidCommand) {
            try await vm.save()
        }
    }

    @Test("connectAndListToolsPopulatesTools")
    func connectAndListToolsPopulatesTools() async throws {
        let fixture = try makeFixture()
        let stub = StubToolsClient()
        stub.listResult = [
            MCPToolSummary(id: "t1", name: "t1", description: "one", parametersJSON: nil),
            MCPToolSummary(id: "t2", name: "t2", description: nil, parametersJSON: nil),
            MCPToolSummary(id: "t3", name: "t3", description: "three", parametersJSON: "{}"),
        ]
        let vm = MCPServerDetailViewModel(store: fixture.store, client: stub)
        await vm.load(serverId: nil)
        vm.updateName("x")
        vm.updateURL("https://x.com")

        await vm.connectAndListTools()
        #expect(vm.tools.count == 3)
        #expect(vm.connectionError == nil)
        #expect(vm.lastConnectionAttempt != nil)
    }

    @Test("connectAndListToolsSurfacesErrorOnFailure")
    func connectAndListToolsSurfacesErrorOnFailure() async throws {
        let fixture = try makeFixture()
        let stub = StubToolsClient()
        stub.listError = StubError.boom
        let vm = MCPServerDetailViewModel(store: fixture.store, client: stub)
        await vm.load(serverId: nil)

        await vm.connectAndListTools()
        #expect(vm.tools.isEmpty)
        #expect(vm.connectionError != nil)
    }

    @Test("runToolPopulatesResult")
    func runToolPopulatesResult() async throws {
        let fixture = try makeFixture()
        let stub = StubToolsClient()
        stub.runResult = "hello"
        let vm = MCPServerDetailViewModel(store: fixture.store, client: stub)
        await vm.load(serverId: nil)

        await vm.runTool(name: "t1", argumentsJSON: "{\"q\": \"hi\"}")
        #expect(vm.toolRunResult == "hello")
        #expect(vm.toolRunError == nil)
    }

    @Test("runToolSurfacesError")
    func runToolSurfacesError() async throws {
        let fixture = try makeFixture()
        let stub = StubToolsClient()
        stub.runError = StubError.boom
        let vm = MCPServerDetailViewModel(store: fixture.store, client: stub)
        await vm.load(serverId: nil)

        await vm.runTool(name: "t1", argumentsJSON: "{}")
        #expect(vm.toolRunResult == nil)
        #expect(vm.toolRunError != nil)
    }
}

// MARK: - Test Fixtures

@MainActor
private func makeFixture() throws -> (store: MCPServerStore, directory: URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mcp-detail-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let defaults = UserDefaults(suiteName: "mcp-tests-\(UUID().uuidString)")!
    let store = MCPServerStore(
        directory: dir,
        keychain: InMemoryKeychain(),
        defaults: defaults
    )
    return (store, dir)
}

private final class InMemoryKeychain: KeychainServing, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func save(_ value: String, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }

    func load(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func delete(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}

private final class StubToolsClient: MCPToolsClientProtocol, @unchecked Sendable {
    var listResult: [MCPToolSummary] = []
    var listError: Error?
    var runResult: String = ""
    var runError: Error?

    func connectAndListTools(for config: MCPServerConfig) async throws -> [MCPToolSummary] {
        if let err = listError { throw err }
        return listResult
    }

    func callTool(config: MCPServerConfig, name: String, arguments: [String: Any]) async throws -> String {
        if let err = runError { throw err }
        return runResult
    }
}

private enum StubError: Error { case boom }
