import Foundation
import PTCore

enum ShareDefaultRoute: String, Codable, CaseIterable, Sendable {
    case auto
    case aiChat = "ai_chat"
    case bookshelf
    case ask

    static func current(defaults: UserDefaults = AppConfig.groupDefaults) -> ShareDefaultRoute {
        ShareDefaultRoute(
            rawValue: defaults.string(forKey: AppConfig.Keys.shareDefaultRoute)
                ?? AppConfig.Defaults.defaultShareDefaultRoute
        ) ?? .auto
    }
}

enum SharedInboxRoute: String, Codable, Sendable {
    case bookshelfImport
    case aiChat
    case ask
}

enum SharedInboxRouteFallbackReason: String, Codable, Sendable {
    case bookPayloadRequiresBookshelf
    case nonBookPayloadRequiresAIChat
}

struct SharedInboxFileItem: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case book
        case image
    }

    let id: String
    let filename: String
    let mediaType: String
    let kind: Kind
}

struct SharedInboxEvent: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let createdAt: Date
    let route: SharedInboxRoute
    let text: [String]
    let urls: [String]
    let fileItems: [SharedInboxFileItem]
    let requestedRoute: ShareDefaultRoute
    let fallbackReason: SharedInboxRouteFallbackReason?

    init(
        id: String,
        createdAt: Date,
        route: SharedInboxRoute,
        text: [String],
        urls: [String],
        fileItems: [SharedInboxFileItem],
        requestedRoute: ShareDefaultRoute = .auto,
        fallbackReason: SharedInboxRouteFallbackReason? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.route = route
        self.text = text
        self.urls = urls
        self.fileItems = fileItems
        self.requestedRoute = requestedRoute
        self.fallbackReason = fallbackReason
    }
}

enum SharedInbox {
    static let defaultTTL: TimeInterval = 60 * 60 * 24

    static func inboxURL(containerURL: URL? = nil, fileManager: FileManager = .default) -> URL {
        let container = containerURL ?? AppConfig.appGroupContainerURL(fileManager: fileManager)
        let inbox = container
            .appendingPathComponent("share_handler", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
        try? fileManager.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    static func eventURL(id: String, containerURL: URL? = nil, fileManager: FileManager = .default) -> URL {
        let url = inboxURL(containerURL: containerURL, fileManager: fileManager)
            .appendingPathComponent(id, isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func eventFilesURL(id: String, containerURL: URL? = nil, fileManager: FileManager = .default) -> URL {
        let url = eventURL(id: id, containerURL: containerURL, fileManager: fileManager)
            .appendingPathComponent("files", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func manifestURL(id: String, containerURL: URL? = nil, fileManager: FileManager = .default) -> URL {
        eventURL(id: id, containerURL: containerURL, fileManager: fileManager)
            .appendingPathComponent("event.json")
    }

    static func save(_ event: SharedInboxEvent, containerURL: URL? = nil, fileManager: FileManager = .default) throws {
        cleanupExpiredEvents(containerURL: containerURL, fileManager: fileManager)
        let manifest = manifestURL(id: event.id, containerURL: containerURL, fileManager: fileManager)
        let data = try JSONEncoder().encode(event)
        try data.write(to: manifest, options: .atomic)
    }

    static func loadEvent(id: String, containerURL: URL? = nil, fileManager: FileManager = .default) -> SharedInboxEvent? {
        cleanupExpiredEvents(containerURL: containerURL, fileManager: fileManager)
        return loadEventWithoutCleanup(id: id, containerURL: containerURL, fileManager: fileManager)
    }

    private static func loadEventWithoutCleanup(id: String, containerURL: URL?, fileManager: FileManager) -> SharedInboxEvent? {
        let manifest = manifestURL(id: id, containerURL: containerURL, fileManager: fileManager)
        guard let data = try? Data(contentsOf: manifest) else { return nil }
        return try? JSONDecoder().decode(SharedInboxEvent.self, from: data)
    }

    static func fileURL(
        for item: SharedInboxFileItem,
        eventID: String,
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        eventFilesURL(id: eventID, containerURL: containerURL, fileManager: fileManager)
            .appendingPathComponent(item.filename)
    }

    static func store(
        _ sourceURL: URL,
        eventID: String,
        kind: SharedInboxFileItem.Kind,
        preferredName: String? = nil,
        mediaType: String,
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> SharedInboxFileItem {
        let directory = eventFilesURL(id: eventID, containerURL: containerURL, fileManager: fileManager)
        let destination = uniqueDestination(
            named: preferredName ?? sourceURL.lastPathComponent,
            in: directory,
            fileManager: fileManager
        )
        try fileManager.copyItem(at: sourceURL, to: destination)
        return SharedInboxFileItem(
            id: destination.lastPathComponent,
            filename: destination.lastPathComponent,
            mediaType: mediaType,
            kind: kind
        )
    }

    static func store(
        data: Data,
        filename: String,
        eventID: String,
        kind: SharedInboxFileItem.Kind,
        mediaType: String,
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> SharedInboxFileItem {
        let directory = eventFilesURL(id: eventID, containerURL: containerURL, fileManager: fileManager)
        let destination = uniqueDestination(named: filename, in: directory, fileManager: fileManager)
        try data.write(to: destination, options: .atomic)
        return SharedInboxFileItem(
            id: destination.lastPathComponent,
            filename: destination.lastPathComponent,
            mediaType: mediaType,
            kind: kind
        )
    }

    static func pendingFiles(eventID: String, containerURL: URL? = nil, fileManager: FileManager = .default) -> [URL] {
        guard let event = loadEvent(id: eventID, containerURL: containerURL, fileManager: fileManager) else {
            return []
        }
        return event.fileItems
            .filter { $0.kind == .book }
            .map { fileURL(for: $0, eventID: eventID, containerURL: containerURL, fileManager: fileManager) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    static func consume(eventID: String, containerURL: URL? = nil, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: eventURL(id: eventID, containerURL: containerURL, fileManager: fileManager))
    }

    @discardableResult
    static func cleanupExpiredEvents(
        containerURL: URL? = nil,
        fileManager: FileManager = .default,
        now: Date = Date(),
        ttl: TimeInterval = defaultTTL
    ) -> [String] {
        let root = inboxURL(containerURL: containerURL, fileManager: fileManager)
        let eventDirectories = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var removedIDs: [String] = []
        for candidate in eventDirectories {
            guard (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let id = candidate.lastPathComponent
            let isExpired: Bool
            if let event = loadEventWithoutCleanup(id: id, containerURL: containerURL, fileManager: fileManager) {
                isExpired = now.timeIntervalSince(event.createdAt) > ttl
            } else if let attrs = try? fileManager.attributesOfItem(atPath: candidate.path),
                      let modified = attrs[.modificationDate] as? Date {
                isExpired = now.timeIntervalSince(modified) > ttl
            } else {
                isExpired = false
            }

            if isExpired {
                try? fileManager.removeItem(at: candidate)
                removedIDs.append(id)
            }
        }

        return removedIDs.sorted()
    }

    private static func isImportable(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "pdf" || ext == "epub"
    }

    private static func importableFiles(in directory: URL, fileManager: FileManager) -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { isImportable($0) }
    }

    private static func uniqueDestination(named filename: String, in directory: URL, fileManager: FileManager) -> URL {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: filename).pathExtension
        var attempt = 0

        while true {
            let candidateName: String
            if attempt == 0 {
                candidateName = filename
            } else if ext.isEmpty {
                candidateName = "\(base)-\(attempt)"
            } else {
                candidateName = "\(base)-\(attempt).\(ext)"
            }

            let candidate = directory.appendingPathComponent(candidateName)
            if fileManager.fileExists(atPath: candidate.path) == false {
                return candidate
            }
            attempt += 1
        }
    }
}
