import Foundation
import Testing
@testable import PaperTokReader

@Suite("SharedInboxImportProcessor")
struct SharedInboxImportProcessorTests {
    private struct ImportFailure: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    @Test("partial success retains only failed book items for retry")
    func partialSuccessRetainsOnlyFailures() async throws {
        let containerURL = try makeContainerURL(prefix: "SharedInboxImportProcessorPartial")
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let eventID = UUID().uuidString
        let first = try makeStoredBookItem(filename: "first.epub", eventID: eventID, containerURL: containerURL)
        let second = try makeStoredBookItem(filename: "second.epub", eventID: eventID, containerURL: containerURL)
        try SharedInbox.save(
            SharedInboxEvent(
                id: eventID,
                createdAt: Date(),
                route: .bookshelfImport,
                text: [],
                urls: [],
                fileItems: [first, second]
            ),
            containerURL: containerURL
        )

        let processor = SharedInboxImportProcessor(
            dependencies: makeDependencies(containerURL: containerURL) { url in
                if url.lastPathComponent == second.filename {
                    return ImportFailure(message: "synthetic import failure")
                }
                return nil
            }
        )

        let result = await processor.process(eventID: eventID)
        let persisted = try #require(SharedInbox.loadEvent(id: eventID, containerURL: containerURL))

        #expect(result.importedCount == 1)
        #expect(result.remainingCount == 1)
        #expect(result.discardedCount == 0)
        #expect(result.didConsumeEvent == false)
        #expect(result.errorMessage == "synthetic import failure")
        #expect(persisted.fileItems == [second])
    }

    @Test("full success consumes the shared inbox event")
    func fullSuccessConsumesEvent() async throws {
        let containerURL = try makeContainerURL(prefix: "SharedInboxImportProcessorSuccess")
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let eventID = UUID().uuidString
        let first = try makeStoredBookItem(filename: "first.pdf", eventID: eventID, containerURL: containerURL)
        let second = try makeStoredBookItem(filename: "second.epub", eventID: eventID, containerURL: containerURL)
        try SharedInbox.save(
            SharedInboxEvent(
                id: eventID,
                createdAt: Date(),
                route: .bookshelfImport,
                text: [],
                urls: [],
                fileItems: [first, second]
            ),
            containerURL: containerURL
        )

        let processor = SharedInboxImportProcessor(
            dependencies: makeDependencies(containerURL: containerURL) { _ in nil }
        )

        let result = await processor.process(eventID: eventID)

        #expect(result.importedCount == 2)
        #expect(result.remainingCount == 0)
        #expect(result.discardedCount == 0)
        #expect(result.didConsumeEvent)
        #expect(result.errorMessage == nil)
        #expect(SharedInbox.loadEvent(id: eventID, containerURL: containerURL) == nil)
    }

    @Test("full success can retain the shared inbox event for diagnostics")
    func fullSuccessCanRetainEventForDiagnostics() async throws {
        let containerURL = try makeContainerURL(prefix: "SharedInboxImportProcessorRetained")
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let eventID = UUID().uuidString
        let book = try makeStoredBookItem(filename: "retained.epub", eventID: eventID, containerURL: containerURL)
        try SharedInbox.save(
            SharedInboxEvent(
                id: eventID,
                createdAt: Date(),
                route: .bookshelfImport,
                text: [],
                urls: [],
                fileItems: [book]
            ),
            containerURL: containerURL
        )

        let processor = SharedInboxImportProcessor(
            dependencies: .init(
                loadEvent: { lookupEventID in
                    SharedInbox.loadEvent(id: lookupEventID, containerURL: containerURL)
                },
                saveEvent: { event in
                    try SharedInbox.save(event, containerURL: containerURL)
                },
                consumeEvent: { _ in
                    // Simulate a cleanup policy that keeps successful events for diagnostics.
                },
                finalizeSuccessfulUse: { _ in
                    .retained
                },
                fileURL: { item, lookupEventID in
                    SharedInbox.fileURL(for: item, eventID: lookupEventID, containerURL: containerURL)
                },
                fileExists: { url in
                    FileManager.default.fileExists(atPath: url.path)
                },
                fileSize: { url in
                    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
                },
                importBook: { _ in nil }
            )
        )

        let result = await processor.process(eventID: eventID)

        #expect(result.importedCount == 1)
        #expect(result.remainingCount == 0)
        #expect(result.discardedCount == 0)
        #expect(result.didConsumeEvent == false)
        #expect(result.errorMessage == nil)
        #expect(SharedInbox.loadEvent(id: eventID, containerURL: containerURL) != nil)
    }

    @Test("missing shared files are discarded instead of staying pending forever")
    func missingFilesAreDiscarded() async throws {
        let containerURL = try makeContainerURL(prefix: "SharedInboxImportProcessorMissing")
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let eventID = UUID().uuidString
        let missing = SharedInboxFileItem(
            id: "missing.epub",
            filename: "missing.epub",
            mediaType: "application/epub+zip",
            kind: .book
        )
        try SharedInbox.save(
            SharedInboxEvent(
                id: eventID,
                createdAt: Date(),
                route: .bookshelfImport,
                text: [],
                urls: [],
                fileItems: [missing]
            ),
            containerURL: containerURL
        )

        let processor = SharedInboxImportProcessor(
            dependencies: makeDependencies(containerURL: containerURL) { _ in
                Issue.record("importBook should not be called for missing files")
                return nil
            }
        )

        let result = await processor.process(eventID: eventID)

        #expect(result.importedCount == 0)
        #expect(result.remainingCount == 0)
        #expect(result.discardedCount == 1)
        #expect(result.didConsumeEvent)
        #expect(result.errorMessage != nil)
        #expect(SharedInbox.loadEvent(id: eventID, containerURL: containerURL) == nil)
    }

    @Test("oversized attachment is rejected before processing")
    func oversizedAttachmentRejected() async throws {
        let containerURL = try makeContainerURL(prefix: "SharedInboxImportProcessorOversize")
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let eventID = UUID().uuidString
        // Create a file larger than 1 MB limit
        let largeData = Data(repeating: 0x41, count: 2_000_001)
        let book = try SharedInbox.store(
            data: largeData,
            filename: "big.epub",
            eventID: eventID,
            kind: .book,
            mediaType: "application/epub+zip",
            containerURL: containerURL
        )
        try SharedInbox.save(
            SharedInboxEvent(
                id: eventID,
                createdAt: Date(),
                route: .bookshelfImport,
                text: [],
                urls: [],
                fileItems: [book]
            ),
            containerURL: containerURL
        )

        var settings = ShareAndShortcutsSettings.default
        settings.maxAttachmentSizeMB = 1

        let processor = SharedInboxImportProcessor(
            dependencies: makeDependencies(containerURL: containerURL) { _ in
                Issue.record("importBook should not be called for oversized files")
                return nil
            },
            settings: settings
        )

        let result = await processor.process(eventID: eventID)

        #expect(result.importedCount == 0)
        #expect(result.remainingCount == 1)
        #expect(result.errorMessage != nil)
        #expect(result.didConsumeEvent == false)
    }

    @Test("over-count attachments are rejected before processing")
    func overCountAttachmentsRejected() async throws {
        let containerURL = try makeContainerURL(prefix: "SharedInboxImportProcessorOvercount")
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let eventID = UUID().uuidString
        var items: [SharedInboxFileItem] = []
        for i in 0..<4 {
            let item = try makeStoredBookItem(
                filename: "book\(i).epub",
                eventID: eventID,
                containerURL: containerURL
            )
            items.append(item)
        }
        try SharedInbox.save(
            SharedInboxEvent(
                id: eventID,
                createdAt: Date(),
                route: .bookshelfImport,
                text: [],
                urls: [],
                fileItems: items
            ),
            containerURL: containerURL
        )

        var settings = ShareAndShortcutsSettings.default
        settings.maxAttachmentCount = 2

        let processor = SharedInboxImportProcessor(
            dependencies: makeDependencies(containerURL: containerURL) { _ in
                Issue.record("importBook should not be called for over-count")
                return nil
            },
            settings: settings
        )

        let result = await processor.process(eventID: eventID)

        #expect(result.importedCount == 0)
        #expect(result.remainingCount == 4)
        #expect(result.errorMessage != nil)
        #expect(result.didConsumeEvent == false)
    }

    private func makeContainerURL(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeStoredBookItem(filename: String, eventID: String, containerURL: URL) throws -> SharedInboxFileItem {
        try SharedInbox.store(
            data: Data("shared-book".utf8),
            filename: filename,
            eventID: eventID,
            kind: .book,
            mediaType: filename.hasSuffix(".pdf") ? "application/pdf" : "application/epub+zip",
            containerURL: containerURL
        )
    }

    private func makeDependencies(
        containerURL: URL,
        importBook: @escaping @Sendable (URL) async -> Error?
    ) -> SharedInboxImportProcessor.Dependencies {
        .init(
            loadEvent: { eventID in
                SharedInbox.loadEvent(id: eventID, containerURL: containerURL)
            },
            saveEvent: { event in
                try SharedInbox.save(event, containerURL: containerURL)
            },
            consumeEvent: { eventID in
                SharedInbox.consume(eventID: eventID, containerURL: containerURL)
            },
            finalizeSuccessfulUse: { eventID in
                SharedInbox.consume(eventID: eventID, containerURL: containerURL)
                return .consumed
            },
            fileURL: { item, eventID in
                SharedInbox.fileURL(for: item, eventID: eventID, containerURL: containerURL)
            },
            fileExists: { url in
                FileManager.default.fileExists(atPath: url.path)
            },
            fileSize: { url in
                (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
            },
            importBook: importBook
        )
    }
}
