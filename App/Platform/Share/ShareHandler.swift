#if os(iOS)
import Foundation
import UniformTypeIdentifiers
import PTCore

enum ShareHandler {
    struct Dependencies {
        let saveEvent: @Sendable (SharedInboxEvent) throws -> Void

        static let live = Dependencies(saveEvent: { event in
            try SharedInbox.save(event)
        })
    }

    static let supportedBookTypes: [UTType] = [
        .pdf,
        UTType("org.idpf.epub-container") ?? .data,
    ]

    static func captureEvent(
        from items: [NSItemProvider],
        eventID: String,
        requestedRoute: ShareDefaultRoute = .auto,
        dependencies: Dependencies = .live
    ) async -> SharedInboxEvent? {
        var text: [String] = []
        var urls: [String] = []
        var fileItems: [SharedInboxFileItem] = []

        for item in items {
            if let book = await loadBook(from: item, eventID: eventID) {
                fileItems.append(book)
                continue
            }

            if let image = await loadImage(from: item, eventID: eventID, index: fileItems.count) {
                fileItems.append(image)
                continue
            }

            if let url = await loadURLString(from: item) {
                urls.append(url)
                continue
            }

            if let plainText = await loadPlainText(from: item) {
                text.append(plainText)
            }
        }

        let routing = resolveRoute(
            requestedRoute: requestedRoute,
            fileItems: fileItems,
            text: text,
            urls: urls
        )
        guard let route = routing.route else { return nil }

        let event = SharedInboxEvent(
            id: eventID,
            createdAt: Date(),
            route: route,
            text: text,
            urls: urls,
            fileItems: fileItems,
            requestedRoute: requestedRoute,
            fallbackReason: routing.fallbackReason
        )

        do {
            try dependencies.saveEvent(event)
            return event
        } catch {
            return nil
        }
    }

    private static func resolveRoute(
        requestedRoute: ShareDefaultRoute,
        fileItems: [SharedInboxFileItem],
        text: [String],
        urls: [String]
    ) -> (route: SharedInboxRoute?, fallbackReason: SharedInboxRouteFallbackReason?) {
        let hasBooks = fileItems.contains(where: { $0.kind == .book })
        let hasAIContent = text.isEmpty == false || urls.isEmpty == false || fileItems.contains(where: { $0.kind == .image })

        switch requestedRoute {
        case .auto:
            if hasBooks {
                return (.bookshelfImport, nil)
            }
            if hasAIContent {
                return (.aiChat, nil)
            }
            return (nil, nil)
        case .aiChat:
            if hasBooks {
                return (.bookshelfImport, .bookPayloadRequiresBookshelf)
            }
            if hasAIContent {
                return (.aiChat, nil)
            }
            return (nil, nil)
        case .bookshelf:
            if hasBooks {
                return (.bookshelfImport, nil)
            }
            if hasAIContent {
                return (.aiChat, .nonBookPayloadRequiresAIChat)
            }
            return (nil, nil)
        case .ask:
            if hasBooks {
                return (.bookshelfImport, .bookPayloadRequiresBookshelf)
            }
            if hasAIContent {
                return (.ask, nil)
            }
            return (nil, nil)
        }
    }

    private static func loadBook(from item: NSItemProvider, eventID: String) async -> SharedInboxFileItem? {
        for type in supportedBookTypes {
            if item.hasItemConformingToTypeIdentifier(type.identifier) {
                if let url = try? await loadURL(from: item, type: type) {
                    return try? SharedInbox.store(
                        url,
                        eventID: eventID,
                        kind: .book,
                        preferredName: url.lastPathComponent,
                        mediaType: type.preferredMIMEType ?? "application/octet-stream"
                    )
                }
            }
        }
        return nil
    }

    private static func loadImage(from item: NSItemProvider, eventID: String, index: Int) async -> SharedInboxFileItem? {
        let imageType = UTType.image
        guard item.hasItemConformingToTypeIdentifier(imageType.identifier),
              let data = try? await loadData(from: item, typeIdentifier: imageType.identifier) else {
            return nil
        }

        let filename = "shared-image-\(index + 1).bin"
        return try? SharedInbox.store(
            data: data,
            filename: filename,
            eventID: eventID,
            kind: .image,
            mediaType: imageType.preferredMIMEType ?? "application/octet-stream"
        )
    }

    private static func loadURLString(from item: NSItemProvider) async -> String? {
        guard item.hasItemConformingToTypeIdentifier(UTType.url.identifier) else {
            return nil
        }
        if let url = try? await loadURL(from: item, type: .url) {
            return url.absoluteString
        }
        return nil
    }

    private static func loadPlainText(from item: NSItemProvider) async -> String? {
        guard item.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else {
            return nil
        }
        guard let value = try? await loadText(from: item, typeIdentifier: UTType.plainText.identifier) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func loadURL(from item: NSItemProvider, type: UTType) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            item.loadItem(forTypeIdentifier: type.identifier, options: nil) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = data as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadData(from item: NSItemProvider, typeIdentifier: String) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            item.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    private static func loadText(from item: NSItemProvider, typeIdentifier: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            item.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { payload, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let text = payload as? String {
                    continuation.resume(returning: text)
                } else if let text = payload as? NSString {
                    continuation.resume(returning: text as String)
                } else if let data = payload as? Data,
                          let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else if let url = payload as? URL,
                          let text = try? String(contentsOf: url) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
#endif
