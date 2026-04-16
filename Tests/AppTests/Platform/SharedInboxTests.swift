import Foundation
import Testing
@testable import PaperTokReader

@Suite("SharedInbox")
struct SharedInboxTests {
    @Test("shared event files live under share_handler/inbox/<eventId>/files")
    func eventFilesFollowSpecPath() throws {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedInboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let filesURL = SharedInbox.eventFilesURL(id: "event-1", containerURL: containerURL)
        #expect(filesURL.path.hasSuffix("/share_handler/inbox/event-1/files"))
    }

    @Test("expired shared events are removed by TTL cleanup")
    func expiredEventsAreRemoved() throws {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedInboxCleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let expiredDate = Date(timeIntervalSince1970: 1_700_000_000)
        let now = expiredDate.addingTimeInterval(60 * 60 * 25)
        let event = SharedInboxEvent(
            id: "expired-event",
            createdAt: expiredDate,
            route: .aiChat,
            text: ["hello from share"],
            urls: [],
            fileItems: []
        )

        try SharedInbox.save(event, containerURL: containerURL)
        let removed = SharedInbox.cleanupExpiredEvents(
            containerURL: containerURL,
            now: now,
            ttl: 60 * 60 * 24
        )

        #expect(removed == ["expired-event"])
        let deletedEventPath = containerURL
            .appendingPathComponent("share_handler", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .appendingPathComponent("expired-event", isDirectory: true)
            .path
        #expect(FileManager.default.fileExists(atPath: deletedEventPath) == false)
    }

    @Test("configured share TTL drives manual cleanup")
    func configuredTTLCleanupUsesStoredDays() throws {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedInboxConfiguredCleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let suiteName = "SharedInboxConfiguredCleanup.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settingsStore = ShareAndShortcutsSettingsStore(defaults: defaults)
        settingsStore.save(
            {
                var s = ShareAndShortcutsSettings.default
                s.defaultRoute = .auto
                s.ttlDays = 1
                s.cleanupAfterUse = true
                return s
            }()
        )

        let expiredDate = Date(timeIntervalSince1970: 1_700_000_000)
        let event = SharedInboxEvent(
            id: "configured-expired-event",
            createdAt: expiredDate,
            route: .aiChat,
            text: ["hello"],
            urls: [],
            fileItems: []
        )
        try SharedInbox.save(event, containerURL: containerURL)

        let report = ShareInboxMaintenance.cleanupNow(
            settingsStore: settingsStore,
            containerURL: containerURL,
            now: expiredDate.addingTimeInterval(60 * 60 * 48)
        )

        #expect(report.removedEventIDs == ["configured-expired-event"])
        #expect(report.remainingEventCount == 0)
        #expect(settingsStore.lastCleanupMetadata?.removedCount == 1)
    }

    @Test("diagnostics snapshot uses stored TTL days")
    func diagnosticsSnapshotUsesStoredTTLDays() throws {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedInboxDiagnosticsTTL-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let suiteName = "SharedInboxDiagnosticsTTL.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settingsStore = ShareAndShortcutsSettingsStore(defaults: defaults)
        settingsStore.save(
            {
                var s = ShareAndShortcutsSettings.default
                s.ttlDays = 7
                return s
            }()
        )

        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        try SharedInbox.save(
            SharedInboxEvent(
                id: "diagnostics-ttl-event",
                createdAt: createdAt,
                route: .aiChat,
                text: ["hello"],
                urls: [],
                fileItems: []
            ),
            containerURL: containerURL
        )

        let snapshot = SharedInbox.diagnosticsSnapshot(
            defaults: defaults,
            containerURL: containerURL,
            now: createdAt.addingTimeInterval(60 * 60 * 24 * 2)
        )

        #expect(snapshot.pendingEventCount == 1)
        #expect(snapshot.storageRetention == TimeInterval(7 * 24 * 60 * 60))
    }

    @Test("successful use can preserve inbox events when cleanup-after-use is disabled")
    func successfulUseCanRetainEventForDiagnostics() throws {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedInboxRetention-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let suiteName = "SharedInboxRetention.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settingsStore = ShareAndShortcutsSettingsStore(defaults: defaults)
        settingsStore.save(
            {
                var s = ShareAndShortcutsSettings.default
                s.defaultRoute = .ask
                s.ttlDays = 7
                s.cleanupAfterUse = false
                return s
            }()
        )

        let event = SharedInboxEvent(
            id: "retained-event",
            createdAt: Date(),
            route: .ask,
            text: ["Keep me around"],
            urls: [],
            fileItems: []
        )
        try SharedInbox.save(event, containerURL: containerURL)

        let disposition = ShareInboxMaintenance.finalizeSuccessfulUse(
            eventID: event.id,
            settingsStore: settingsStore,
            containerURL: containerURL
        )

        #expect(disposition == .retained)
        #expect(SharedInbox.loadEvent(id: event.id, containerURL: containerURL) != nil)
    }
}
