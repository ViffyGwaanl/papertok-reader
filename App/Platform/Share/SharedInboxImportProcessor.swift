import Foundation
import PTCore

struct SharedInboxImportProcessor {
    struct Result: Equatable {
        let importedCount: Int
        let remainingCount: Int
        let discardedCount: Int
        let didConsumeEvent: Bool
        let errorMessage: String?

        var shouldShowError: Bool {
            errorMessage != nil
        }
    }

    struct Dependencies {
        let loadEvent: @Sendable (String) -> SharedInboxEvent?
        let saveEvent: @Sendable (SharedInboxEvent) throws -> Void
        let consumeEvent: @Sendable (String) -> Void
        let finalizeSuccessfulUse: @Sendable (String) -> ShareInboxMaintenanceDisposition
        let fileURL: @Sendable (SharedInboxFileItem, String) -> URL
        let fileExists: @Sendable (URL) -> Bool
        let importBook: @Sendable (URL) async -> Error?

        static func live(importBook: @escaping @Sendable (URL) async -> Error?) -> Dependencies {
            Dependencies(
                loadEvent: { eventID in
                    SharedInbox.loadEvent(id: eventID)
                },
                saveEvent: { event in
                    try SharedInbox.save(event)
                },
                consumeEvent: { eventID in
                    SharedInbox.consume(eventID: eventID)
                },
                finalizeSuccessfulUse: { eventID in
                    ShareInboxMaintenance.finalizeSuccessfulUse(eventID: eventID)
                },
                fileURL: { item, eventID in
                    SharedInbox.fileURL(for: item, eventID: eventID)
                },
                fileExists: { url in
                    FileManager.default.fileExists(atPath: url.path)
                },
                importBook: importBook
            )
        }
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    init(importBook: @escaping @Sendable (URL) async -> Error?) {
        self.init(dependencies: .live(importBook: importBook))
    }

    func process(eventID: String?) async -> Result {
        guard let eventID else {
            return .init(
                importedCount: 0,
                remainingCount: 0,
                discardedCount: 0,
                didConsumeEvent: false,
                errorMessage: String(localized: "share.error.content_unavailable")
            )
        }

        guard let event = dependencies.loadEvent(eventID) else {
            return .init(
                importedCount: 0,
                remainingCount: 0,
                discardedCount: 0,
                didConsumeEvent: false,
                errorMessage: String(localized: "share.error.content_unavailable")
            )
        }

        guard event.route == .bookshelfImport else {
            return .init(
                importedCount: 0,
                remainingCount: 0,
                discardedCount: 0,
                didConsumeEvent: false,
                errorMessage: String(localized: "share.error.route_requires_bookshelf")
            )
        }

        let bookItems = event.fileItems.filter { $0.kind == .book }
        guard bookItems.isEmpty == false else {
            dependencies.consumeEvent(eventID)
            return .init(
                importedCount: 0,
                remainingCount: 0,
                discardedCount: 0,
                didConsumeEvent: true,
                errorMessage: String(localized: "share.error.content_unavailable")
            )
        }

        var importedCount = 0
        var discardedCount = 0
        var remainingBookItems: [SharedInboxFileItem] = []
        var errorMessage: String?

        for item in bookItems {
            let url = dependencies.fileURL(item, eventID)
            guard dependencies.fileExists(url) else {
                discardedCount += 1
                errorMessage = errorMessage ?? String(localized: "share.error.content_unavailable")
                continue
            }

            if let error = await dependencies.importBook(url) {
                remainingBookItems.append(item)
                errorMessage = AppLocalization.userFacingErrorMessage(
                    for: error,
                    fallbackKey: "share.error.cannot_process"
                )
            } else {
                importedCount += 1
            }
        }

        guard remainingBookItems.isEmpty == false else {
            let disposition = dependencies.finalizeSuccessfulUse(eventID)
            return .init(
                importedCount: importedCount,
                remainingCount: 0,
                discardedCount: discardedCount,
                didConsumeEvent: disposition == .consumed,
                errorMessage: errorMessage
            )
        }

        do {
            let updatedEvent = SharedInboxEvent(
                id: event.id,
                createdAt: event.createdAt,
                route: event.route,
                text: event.text,
                urls: event.urls,
                fileItems: event.fileItems.filter { $0.kind != .book } + remainingBookItems
            )
            try dependencies.saveEvent(updatedEvent)
        } catch {
            return .init(
                importedCount: importedCount,
                remainingCount: remainingBookItems.count,
                discardedCount: discardedCount,
                didConsumeEvent: false,
                errorMessage: AppLocalization.userFacingErrorMessage(
                    for: error,
                    fallbackKey: "share.error.cannot_process"
                )
            )
        }

        return .init(
            importedCount: importedCount,
            remainingCount: remainingBookItems.count,
            discardedCount: discardedCount,
            didConsumeEvent: false,
            errorMessage: errorMessage
        )
    }
}
