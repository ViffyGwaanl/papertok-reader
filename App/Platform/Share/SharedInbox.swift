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

    static func persist(_ route: ShareDefaultRoute, defaults: UserDefaults = AppConfig.groupDefaults) {
        defaults.set(route.rawValue, forKey: AppConfig.Keys.shareDefaultRoute)
    }

    var localizedTitle: String {
        switch self {
        case .auto:
            return String(localized: "share.settings.route.auto")
        case .aiChat:
            return String(localized: "share.send_to_ai")
        case .bookshelf:
            return String(localized: "share.add_to_library")
        case .ask:
            return String(localized: "share.settings.route.ask")
        }
    }
}

enum SharedInboxRoute: String, Codable, Sendable {
    case bookshelfImport
    case aiChat
    case ask

    var localizedTitle: String {
        switch self {
        case .bookshelfImport:
            return String(localized: "share.add_to_library")
        case .aiChat:
            return String(localized: "share.send_to_ai")
        case .ask:
            return String(localized: "share.settings.route.ask")
        }
    }
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

struct SharedInboxDiagnosticsSnapshot: Equatable, Sendable {
    struct LatestEvent: Equatable, Sendable {
        let id: String
        let createdAt: Date
        let route: SharedInboxRoute
        let fileCount: Int
        let textCount: Int
        let urlCount: Int
    }

    let defaultRoute: ShareDefaultRoute
    let pendingEventCount: Int
    let storageRetention: TimeInterval
    let latestEvent: LatestEvent?
}

enum ShareSessionTarget: String, Codable, CaseIterable, Sendable {
    case automatic
    case newConversation = "new_conversation"
    case currentConversation = "current_conversation"

    var localizedTitle: String {
        switch self {
        case .automatic:
            return String(localized: "share.settings.session_target.automatic")
        case .newConversation:
            return String(localized: "share.settings.session_target.new_conversation")
        case .currentConversation:
            return String(localized: "share.settings.session_target.current_conversation")
        }
    }
}

struct ShareAndShortcutsSettings: Codable, Equatable, Sendable {
    var defaultRoute: ShareDefaultRoute
    var ttlDays: Int
    var cleanupAfterUse: Bool
    var askBeforeRouting: Bool
    var sessionTarget: ShareSessionTarget
    var maxAttachmentSizeMB: Int
    var maxAttachmentCount: Int

    var retentionInterval: TimeInterval? {
        guard ttlDays > 0 else { return nil }
        return TimeInterval(ttlDays * 24 * 60 * 60)
    }

    static let `default` = ShareAndShortcutsSettings(
        defaultRoute: .auto,
        ttlDays: 7,
        cleanupAfterUse: true,
        askBeforeRouting: false,
        sessionTarget: .automatic,
        maxAttachmentSizeMB: 10,
        maxAttachmentCount: 5
    )
}

struct ShareInboxCleanupMetadata: Codable, Equatable, Sendable {
    let lastRunAt: Date
    let removedCount: Int
}

struct ShareAndShortcutsSettingsStore {
    static let storageKey = "share_and_shortcuts.settings.v1"
    static let legacyShareModeKey = "sharePanelModeV1"
    static let legacyCleanupAfterUseKey = "sharePanelCleanupAfterUseV1"
    static let legacyTTLDaysKey = "sharePanelTtlDaysV1"
    static let cleanupMetadataKey = "share_and_shortcuts.cleanup_metadata.v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = AppConfig.groupDefaults) {
        self.defaults = defaults
    }

    func load() -> ShareAndShortcutsSettings {
        if let data = defaults.data(forKey: Self.storageKey),
           let settings = try? JSONDecoder().decode(ShareAndShortcutsSettings.self, from: data) {
            return settings
        }

        let routeRaw = defaults.string(forKey: AppConfig.Keys.shareDefaultRoute)
            ?? defaults.string(forKey: Self.legacyShareModeKey)
        let defaultRoute = ShareDefaultRoute(rawValue: routeRaw ?? "") ?? .auto
        let ttlDays = defaults.object(forKey: Self.legacyTTLDaysKey) != nil
            ? defaults.integer(forKey: Self.legacyTTLDaysKey)
            : ShareAndShortcutsSettings.default.ttlDays
        let cleanupAfterUse = defaults.object(forKey: Self.legacyCleanupAfterUseKey) != nil
            ? defaults.bool(forKey: Self.legacyCleanupAfterUseKey)
            : ShareAndShortcutsSettings.default.cleanupAfterUse

        return ShareAndShortcutsSettings(
            defaultRoute: defaultRoute,
            ttlDays: ttlDays,
            cleanupAfterUse: cleanupAfterUse,
            askBeforeRouting: ShareAndShortcutsSettings.default.askBeforeRouting,
            sessionTarget: ShareAndShortcutsSettings.default.sessionTarget,
            maxAttachmentSizeMB: ShareAndShortcutsSettings.default.maxAttachmentSizeMB,
            maxAttachmentCount: ShareAndShortcutsSettings.default.maxAttachmentCount
        )
    }

    func save(_ settings: ShareAndShortcutsSettings) {
        ShareDefaultRoute.persist(settings.defaultRoute, defaults: defaults)
        defaults.set(settings.defaultRoute.rawValue, forKey: Self.legacyShareModeKey)
        defaults.set(settings.ttlDays, forKey: Self.legacyTTLDaysKey)
        defaults.set(settings.cleanupAfterUse, forKey: Self.legacyCleanupAfterUseKey)
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    var lastCleanupMetadata: ShareInboxCleanupMetadata? {
        guard let data = defaults.data(forKey: Self.cleanupMetadataKey) else { return nil }
        return try? JSONDecoder().decode(ShareInboxCleanupMetadata.self, from: data)
    }

    func saveCleanupMetadata(_ metadata: ShareInboxCleanupMetadata) {
        if let data = try? JSONEncoder().encode(metadata) {
            defaults.set(data, forKey: Self.cleanupMetadataKey)
        }
    }
}

enum ShareInboxMaintenanceDisposition: Equatable, Sendable {
    case consumed
    case retained
}

struct ShareInboxCleanupReport: Equatable, Sendable {
    let removedEventIDs: [String]
    let remainingEventCount: Int
}

enum ShareInboxMaintenance {
    static func cleanupNow(
        settingsStore: ShareAndShortcutsSettingsStore = ShareAndShortcutsSettingsStore(),
        containerURL: URL? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> ShareInboxCleanupReport {
        let settings = settingsStore.load()
        let ttl: TimeInterval? = settings.ttlDays > 0
            ? TimeInterval(settings.ttlDays * 24 * 60 * 60)
            : nil

        let removedEventIDs = ttl.map {
            SharedInbox.cleanupExpiredEvents(
                containerURL: containerURL,
                fileManager: fileManager,
                now: now,
                ttl: $0
            )
        } ?? []
        let remainingEventCount = SharedInbox.pendingEvents(
            containerURL: containerURL,
            fileManager: fileManager,
            now: now,
            ttl: ttl
        ).count

        settingsStore.saveCleanupMetadata(
            ShareInboxCleanupMetadata(lastRunAt: now, removedCount: removedEventIDs.count)
        )

        return ShareInboxCleanupReport(
            removedEventIDs: removedEventIDs,
            remainingEventCount: remainingEventCount
        )
    }

    static func finalizeSuccessfulUse(
        eventID: String,
        settingsStore: ShareAndShortcutsSettingsStore = ShareAndShortcutsSettingsStore(),
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> ShareInboxMaintenanceDisposition {
        guard settingsStore.load().cleanupAfterUse else {
            return .retained
        }
        SharedInbox.consume(eventID: eventID, containerURL: containerURL, fileManager: fileManager)
        return .consumed
    }
}

enum ShareInboxDiagnosticAction: String, Codable, Sendable {
    case capture
    case handoff
    case cleanup
}

enum ShareInboxDiagnosticStatus: String, Codable, Sendable {
    case pending
    case success
    case failure
    case skipped
}

struct ShareInboxDiagnosticEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let action: ShareInboxDiagnosticAction
    let status: ShareInboxDiagnosticStatus
    let eventID: String?
    let route: SharedInboxRoute?
    let requestedRoute: ShareDefaultRoute?
    let fallbackReason: SharedInboxRouteFallbackReason?
    let textCount: Int
    let urlCount: Int
    let bookCount: Int
    let imageCount: Int
    let importedCount: Int
    let remainingCount: Int
    let discardedCount: Int
    let removedCount: Int
    let message: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        action: ShareInboxDiagnosticAction,
        status: ShareInboxDiagnosticStatus,
        eventID: String?,
        route: SharedInboxRoute?,
        requestedRoute: ShareDefaultRoute?,
        fallbackReason: SharedInboxRouteFallbackReason?,
        textCount: Int,
        urlCount: Int,
        bookCount: Int,
        imageCount: Int,
        importedCount: Int,
        remainingCount: Int,
        discardedCount: Int,
        removedCount: Int,
        message: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.action = action
        self.status = status
        self.eventID = eventID
        self.route = route
        self.requestedRoute = requestedRoute
        self.fallbackReason = fallbackReason
        self.textCount = textCount
        self.urlCount = urlCount
        self.bookCount = bookCount
        self.imageCount = imageCount
        self.importedCount = importedCount
        self.remainingCount = remainingCount
        self.discardedCount = discardedCount
        self.removedCount = removedCount
        self.message = message
    }
}

struct ShareInboxDiagnosticsStore {
    static let storageKey = "share_inbox_diagnostics.v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = AppConfig.groupDefaults) {
        self.defaults = defaults
    }

    var entries: [ShareInboxDiagnosticEntry] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([ShareInboxDiagnosticEntry].self, from: data)) ?? []
    }

    func append(_ entry: ShareInboxDiagnosticEntry) {
        var nextEntries = entries
        nextEntries.append(entry)
        if nextEntries.count > 200 {
            nextEntries.removeFirst(nextEntries.count - 200)
        }
        guard let data = try? JSONEncoder().encode(nextEntries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

struct ShareInboxSummary: Equatable, Sendable {
    let pendingEventCount: Int
}

struct ShareAndShortcutsSnapshot: Equatable, Sendable {
    let settings: ShareAndShortcutsSettings
    let inboxSummary: ShareInboxSummary
    let recentInboxEvents: [SharedInboxEvent]
    let recentDiagnostics: [ShareInboxDiagnosticEntry]
    let pendingShortcutCallbackCount: Int
    let pendingShortcutStepCount: Int
    let pendingShortcutAIRequestCount: Int
}

struct ShareAndShortcutsSnapshotLoader {
    let settingsStore: ShareAndShortcutsSettingsStore
    let diagnosticsStore: ShareInboxDiagnosticsStore
    let pendingAIRequestStore: PendingAIRequestStore
    let callbacksService: ShortcutsCallbackService
    let pendingShortcutQueue: PendingShortcutQueue
    let containerURL: URL?
    let fileManager: FileManager

    init(
        settingsStore: ShareAndShortcutsSettingsStore = ShareAndShortcutsSettingsStore(),
        diagnosticsStore: ShareInboxDiagnosticsStore = ShareInboxDiagnosticsStore(),
        pendingAIRequestStore: PendingAIRequestStore = PendingAIRequestStore(),
        callbacksService: ShortcutsCallbackService = ShortcutsCallbackService(),
        pendingShortcutQueue: PendingShortcutQueue = PendingShortcutQueue(),
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.settingsStore = settingsStore
        self.diagnosticsStore = diagnosticsStore
        self.pendingAIRequestStore = pendingAIRequestStore
        self.callbacksService = callbacksService
        self.pendingShortcutQueue = pendingShortcutQueue
        self.containerURL = containerURL
        self.fileManager = fileManager
    }

    func load(now: Date = Date()) async -> ShareAndShortcutsSnapshot {
        let settings = settingsStore.load()
        let ttl: TimeInterval? = settings.ttlDays > 0
            ? TimeInterval(settings.ttlDays * 24 * 60 * 60)
            : nil
        let recentInboxEvents = SharedInbox.pendingEvents(
            containerURL: containerURL,
            fileManager: fileManager,
            now: now,
            ttl: ttl
        )
        let recentDiagnostics = diagnosticsStore.entries
            .sorted { $0.createdAt > $1.createdAt }
        let pendingShortcutCallbackCount = callbacksService.allPending().count
        let pendingShortcutStepCount = await pendingShortcutQueue.all()
            .filter { $0.status == .pending || $0.status == .running }
            .count
        let pendingShortcutAIRequestCount = pendingAIRequestStore.requests
            .filter { $0.status == .pending || $0.status == .running }
            .count

        return ShareAndShortcutsSnapshot(
            settings: settings,
            inboxSummary: ShareInboxSummary(pendingEventCount: recentInboxEvents.count),
            recentInboxEvents: recentInboxEvents,
            recentDiagnostics: recentDiagnostics,
            pendingShortcutCallbackCount: pendingShortcutCallbackCount,
            pendingShortcutStepCount: pendingShortcutStepCount,
            pendingShortcutAIRequestCount: pendingShortcutAIRequestCount
        )
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

    static func pendingEvents(
        containerURL: URL? = nil,
        fileManager: FileManager = .default,
        now: Date = Date(),
        ttl: TimeInterval? = defaultTTL
    ) -> [SharedInboxEvent] {
        if let ttl {
            cleanupExpiredEvents(containerURL: containerURL, fileManager: fileManager, now: now, ttl: ttl)
        }

        let root = inboxURL(containerURL: containerURL, fileManager: fileManager)
        let eventDirectories = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return eventDirectories.compactMap { candidate -> SharedInboxEvent? in
            guard (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return loadEventWithoutCleanup(
                id: candidate.lastPathComponent,
                containerURL: containerURL,
                fileManager: fileManager
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func diagnosticsSnapshot(
        defaults: UserDefaults = AppConfig.groupDefaults,
        containerURL: URL? = nil,
        fileManager: FileManager = .default,
        now: Date = Date(),
        ttl: TimeInterval? = nil
    ) -> SharedInboxDiagnosticsSnapshot {
        let resolvedTTL: TimeInterval = ttl ?? {
            let settings = ShareAndShortcutsSettingsStore(defaults: defaults).load()
            guard settings.ttlDays > 0 else { return defaultTTL }
            return TimeInterval(settings.ttlDays * 24 * 60 * 60)
        }()
        let events = pendingEvents(
            containerURL: containerURL,
            fileManager: fileManager,
            now: now,
            ttl: resolvedTTL
        )

        let latestEvent = events.first.map {
            SharedInboxDiagnosticsSnapshot.LatestEvent(
                id: $0.id,
                createdAt: $0.createdAt,
                route: $0.route,
                fileCount: $0.fileItems.count,
                textCount: $0.text.count,
                urlCount: $0.urls.count
            )
        }

        return SharedInboxDiagnosticsSnapshot(
            defaultRoute: ShareDefaultRoute.current(defaults: defaults),
            pendingEventCount: events.count,
            storageRetention: resolvedTTL,
            latestEvent: latestEvent
        )
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
