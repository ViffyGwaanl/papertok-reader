import Foundation
import PTCore

/// Identifies the type of intent backing a queued shortcut step.
enum ShortcutIntentType: String, Codable, Sendable {
    case openBook
    case askAI
    case sendMessage
    case searchBooks
    case getReadingStats
    case createNote
}

enum ShortcutStepStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

/// A successful or failed result for a shortcut step. The textual
/// payload is intentionally simple so it round-trips through
/// `pending_shortcuts.json` even when the app is killed mid-chain.
struct ShortcutResult: Codable, Equatable, Sendable {
    var success: Bool
    var output: String?
    var values: [String: String]
    var errorMessage: String?

    init(
        success: Bool,
        output: String? = nil,
        values: [String: String] = [:],
        errorMessage: String? = nil
    ) {
        self.success = success
        self.output = output
        self.values = values
        self.errorMessage = errorMessage
    }

    static func ok(output: String? = nil, values: [String: String] = [:]) -> ShortcutResult {
        ShortcutResult(success: true, output: output, values: values)
    }

    static func failure(_ error: Error) -> ShortcutResult {
        ShortcutResult(success: false, errorMessage: error.localizedDescription)
    }
}

struct ShortcutStep: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let intent: ShortcutIntentType
    var parameters: [String: String]
    var status: ShortcutStepStatus
    var createdAt: Date
    var result: ShortcutResult?

    init(
        id: UUID = UUID(),
        intent: ShortcutIntentType,
        parameters: [String: String] = [:],
        status: ShortcutStepStatus = .pending,
        createdAt: Date = Date(),
        result: ShortcutResult? = nil
    ) {
        self.id = id
        self.intent = intent
        self.parameters = parameters
        self.status = status
        self.createdAt = createdAt
        self.result = result
    }
}

/// Persistent queue used to chain multi-step Shortcuts execution.
///
/// The queue is persisted to `pending_shortcuts.json` inside the App
/// Group container so that an interrupted multi-step run can resume on
/// the next launch. All mutating operations are funneled through an
/// actor to keep the file consistent.
actor PendingShortcutQueue {
    static let shared = PendingShortcutQueue()

    static let filename = "pending_shortcuts.json"

    private let fileURL: URL
    private var cache: [ShortcutStep] = []
    private var loaded = false

    init(containerURL: URL? = nil) {
        let root = containerURL ?? AppConfig.appGroupContainerURL()
        let directory = root.appendingPathComponent("Intents", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(Self.filename)
    }

    // MARK: - Public API

    func enqueue(_ step: ShortcutStep) {
        loadIfNeeded()
        cache.append(step)
        persist()
    }

    func next() -> ShortcutStep? {
        loadIfNeeded()
        return cache.first { $0.status == .pending }
    }

    func complete(_ step: ShortcutStep, result: ShortcutResult) {
        update(step.id) {
            $0.status = result.success ? .completed : .failed
            $0.result = result
        }
    }

    func cancel(_ step: ShortcutStep) {
        loadIfNeeded()
        cache.removeAll { $0.id == step.id }
        persist()
    }

    func all() -> [ShortcutStep] {
        loadIfNeeded()
        return cache
    }

    func clear() {
        cache = []
        loaded = true
        persist()
    }

    func markRunning(_ step: ShortcutStep) {
        update(step.id) { $0.status = .running }
    }

    // MARK: - Internal helpers

    private func update(_ id: UUID, _ transform: (inout ShortcutStep) -> Void) {
        loadIfNeeded()
        guard let index = cache.firstIndex(where: { $0.id == id }) else { return }
        transform(&cache[index])
        persist()
    }

    private func loadIfNeeded() {
        guard loaded == false else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        cache = (try? JSONDecoder().decode([ShortcutStep].self, from: data)) ?? []
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence is best-effort: an unwritable container shouldn't
            // crash an in-flight intent.
        }
    }
}
