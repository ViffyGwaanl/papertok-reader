import Foundation

/// Abstraction the auto-save timer calls on each tick. Injected by the App target so the
/// service stays decoupled from any specific conversation store.
public protocol MemoryAutoSaveSource: AnyObject, Sendable {
    /// Returns the messages that have been added since the last digest, or nil if nothing
    /// needs to be persisted. Implementations should clear their "dirty" flag when consumed.
    @MainActor func pendingMessagesForDigest() -> [ChatMessage]?
    /// The provider used to build the digest.
    @MainActor var digestProvider: (any ChatModelProvider)? { get }
    /// Directory where memory files should live.
    @MainActor var memoryDirectory: URL? { get }
}

/// Periodically digests recent conversation activity and appends a summary to the daily
/// memory file. Starts a ``Timer`` on the main run loop and drives the source on every tick.
@MainActor
public final class MemoryAutoSaveService {
    public nonisolated static let defaultInterval: TimeInterval = 15 * 60 // 15 minutes

    private weak var source: MemoryAutoSaveSource?
    private let digestService: SessionDigestService
    private var timer: Timer?
    private(set) public var isRunning: Bool = false
    private(set) public var lastError: Error?
    private(set) public var lastSavedAt: Date?

    public init(
        source: MemoryAutoSaveSource,
        digestService: SessionDigestService = SessionDigestService()
    ) {
        self.source = source
        self.digestService = digestService
    }

    /// Begin periodic auto-save. Safe to call repeatedly — the previous timer is replaced.
    public func start(interval: TimeInterval = MemoryAutoSaveService.defaultInterval) {
        stop()
        let clamped = max(30, interval)
        let t = Timer(timeInterval: clamped, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
        self.isRunning = true
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// Perform one digest cycle immediately. Exposed for testing and for manual triggers
    /// like "save now" menu items.
    public func tick() async {
        guard let source else { return }
        guard let messages = source.pendingMessagesForDigest(), !messages.isEmpty else { return }
        guard let provider = source.digestProvider else { return }
        guard let directory = source.memoryDirectory else { return }
        do {
            _ = try await digestService.digestAndAppend(
                messages: messages,
                provider: provider,
                memoryDirectory: directory
            )
            lastSavedAt = Date()
            lastError = nil
        } catch {
            lastError = error
        }
    }

    deinit {
        timer?.invalidate()
    }
}
