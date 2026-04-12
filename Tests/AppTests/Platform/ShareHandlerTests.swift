import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PaperTokReader

@Suite("ShareHandler")
struct ShareHandlerTests {
    private enum SaveFailure: Error {
        case diskFull
    }

    @Test("plain text shares route to AI chat and persist the manifest")
    func plainTextSharesPersistManifest() async throws {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareHandlerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let provider = NSItemProvider(item: "Summarize this abstract" as NSString, typeIdentifier: UTType.plainText.identifier)
        let eventID = UUID().uuidString

        let event = await ShareHandler.captureEvent(
            from: [provider],
            eventID: eventID,
            dependencies: .init(saveEvent: { event in
                try SharedInbox.save(event, containerURL: containerURL)
            })
        )

        let persisted = SharedInbox.loadEvent(id: eventID, containerURL: containerURL)
        #expect(event?.route == .aiChat)
        #expect(event?.text == ["Summarize this abstract"])
        #expect(persisted == event)
    }

    @Test("share capture returns nil when manifest persistence fails")
    func saveFailurePreventsShareRoute() async {
        let provider = NSItemProvider(item: "This should not leak a dead token" as NSString, typeIdentifier: UTType.plainText.identifier)

        let event = await ShareHandler.captureEvent(
            from: [provider],
            eventID: UUID().uuidString,
            dependencies: .init(saveEvent: { _ in
                throw SaveFailure.diskFull
            })
        )

        #expect(event == nil)
    }

    @Test("book file shares route to bookshelf import and copy the payload into the inbox")
    func bookSharesRouteToBookshelfImport() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareHandlerTests-\(UUID().uuidString).epub")
        let sourceData = Data("epub-share-payload".utf8)
        try sourceData.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let provider = NSItemProvider(
            item: sourceURL as NSURL,
            typeIdentifier: "org.idpf.epub-container"
        )
        let eventID = UUID().uuidString
        defer { SharedInbox.consume(eventID: eventID) }

        let event = await ShareHandler.captureEvent(from: [provider], eventID: eventID)
        let persisted = try #require(SharedInbox.loadEvent(id: eventID))
        let fileItem = try #require(event?.fileItems.first)
        let storedURL = SharedInbox.fileURL(for: fileItem, eventID: eventID)

        #expect(event?.route == .bookshelfImport)
        #expect(event?.fileItems.count == 1)
        #expect(fileItem.kind == .book)
        #expect(FileManager.default.fileExists(atPath: storedURL.path))
        #expect(try Data(contentsOf: storedURL) == sourceData)
        #expect(persisted == event)
    }

    @Test("image shares route to AI chat and persist the copied image payload")
    func imageSharesRouteToAIChat() async throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(imageData, nil)
            return nil
        }

        let eventID = UUID().uuidString
        defer { SharedInbox.consume(eventID: eventID) }

        let event = await ShareHandler.captureEvent(from: [provider], eventID: eventID)
        let persisted = try #require(SharedInbox.loadEvent(id: eventID))
        let fileItem = try #require(event?.fileItems.first)
        let storedURL = SharedInbox.fileURL(for: fileItem, eventID: eventID)

        #expect(event?.route == .aiChat)
        #expect(event?.text.isEmpty == true)
        #expect(event?.urls.isEmpty == true)
        #expect(event?.fileItems.count == 1)
        #expect(fileItem.kind == .image)
        #expect(FileManager.default.fileExists(atPath: storedURL.path))
        #expect(try Data(contentsOf: storedURL) == imageData)
        #expect(persisted == event)
    }

    @Test("ask route is preserved for text shares")
    func askRoutePersistsForTextShares() async throws {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareHandlerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let provider = NSItemProvider(item: "Answer this quickly" as NSString, typeIdentifier: UTType.plainText.identifier)
        let eventID = UUID().uuidString

        let event = await ShareHandler.captureEvent(
            from: [provider],
            eventID: eventID,
            requestedRoute: .ask,
            dependencies: .init(saveEvent: { event in
                try SharedInbox.save(event, containerURL: containerURL)
            })
        )

        let persisted = SharedInbox.loadEvent(id: eventID, containerURL: containerURL)
        #expect(event?.route == .ask)
        #expect(event?.requestedRoute == .ask)
        #expect(event?.fallbackReason == nil)
        #expect(persisted == event)
    }

    @Test("ask route falls back to bookshelf when a book file is shared")
    func askRouteFallsBackForBookShares() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareHandlerTests-\(UUID().uuidString).epub")
        try Data("epub-share-payload".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let provider = NSItemProvider(
            item: sourceURL as NSURL,
            typeIdentifier: "org.idpf.epub-container"
        )
        let eventID = UUID().uuidString
        defer { SharedInbox.consume(eventID: eventID) }

        let event = await ShareHandler.captureEvent(
            from: [provider],
            eventID: eventID,
            requestedRoute: .ask
        )

        #expect(event?.route == .bookshelfImport)
        #expect(event?.requestedRoute == .ask)
        #expect(event?.fallbackReason == .bookPayloadRequiresBookshelf)
    }
}
