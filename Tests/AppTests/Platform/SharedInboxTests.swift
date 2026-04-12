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
}
