import Foundation
import Testing
@testable import PaperTokReader

@Suite("ShareAndShortcutsSnapshot")
struct ShareAndShortcutsSnapshotTests {
    @Test("snapshot combines inbox, diagnostics, and shortcuts health")
    func snapshotAggregatesShareAndShortcutsState() async throws {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareAndShortcutsSnapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let suiteName = "ShareAndShortcutsSnapshot.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settingsStore = ShareAndShortcutsSettingsStore(defaults: defaults)
        var snapshotSettings = ShareAndShortcutsSettings.default
        snapshotSettings.defaultRoute = .bookshelf
        settingsStore.save(snapshotSettings)

        let event = SharedInboxEvent(
            id: "snapshot-event",
            createdAt: Date(),
            route: .bookshelfImport,
            text: ["Abstract"],
            urls: ["https://example.com/paper"],
            fileItems: [
                SharedInboxFileItem(
                    id: "file.epub",
                    filename: "file.epub",
                    mediaType: "application/epub+zip",
                    kind: .book
                )
            ],
            requestedRoute: .bookshelf
        )
        try SharedInbox.save(event, containerURL: containerURL)

        let diagnosticsStore = ShareInboxDiagnosticsStore(defaults: defaults)
        diagnosticsStore.append(
            ShareInboxDiagnosticEntry(
                action: .capture,
                status: .success,
                eventID: event.id,
                route: event.route,
                requestedRoute: event.requestedRoute,
                fallbackReason: event.fallbackReason,
                textCount: event.text.count,
                urlCount: event.urls.count,
                bookCount: 1,
                imageCount: 0,
                importedCount: 0,
                remainingCount: 1,
                discardedCount: 0,
                removedCount: 0,
                message: nil
            )
        )

        let requestStore = PendingAIRequestStore(defaults: defaults)
        _ = requestStore.enqueue(prompt: "Summarize this share", images: [], source: .appIntent)

        let callbacks = ShortcutsCallbackService(defaults: defaults)
        callbacks.registerCallback(
            requestId: "callback-1",
            success: URL(string: "shortcuts://x-success"),
            error: URL(string: "shortcuts://x-error")
        )

        let queue = PendingShortcutQueue(containerURL: containerURL)
        await queue.enqueue(ShortcutStep(intent: .sendMessage))

        let snapshot = await ShareAndShortcutsSnapshotLoader(
            settingsStore: settingsStore,
            diagnosticsStore: diagnosticsStore,
            pendingAIRequestStore: requestStore,
            callbacksService: callbacks,
            pendingShortcutQueue: queue,
            containerURL: containerURL
        ).load()

        #expect(snapshot.settings.defaultRoute == .bookshelf)
        #expect(snapshot.inboxSummary.pendingEventCount == 1)
        #expect(snapshot.recentInboxEvents.first?.id == event.id)
        #expect(snapshot.recentDiagnostics.first?.action == .capture)
        #expect(snapshot.pendingShortcutCallbackCount == 1)
        #expect(snapshot.pendingShortcutStepCount == 1)
        #expect(snapshot.pendingShortcutAIRequestCount == 1)
    }
}
