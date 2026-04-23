import Foundation
import Observation

@Observable
public final class FulltextTranslationRuntime: @unchecked Sendable {
    public struct Paragraph: Identifiable, Sendable, Equatable {
        public let id: String
        public let originalText: String
        public var translatedText: String?
        public var status: TranslationStatus
    }

    public enum TranslationStatus: Sendable, Equatable {
        case queued
        case translating
        case ready
        case failed(message: String)
    }

    @MainActor public private(set) var paragraphs: [Paragraph] = []
    @MainActor public var sourceLanguage: String = "auto"
    @MainActor public var targetLanguage: String = "zh-Hans"
    @MainActor public private(set) var isEnabled: Bool = false
    @MainActor public private(set) var inFlightCount: Int = 0

    @MainActor public var hasFailures: Bool {
        paragraphs.contains { if case .failed = $0.status { true } else { false } }
    }

    /// Number of paragraphs whose translation has completed successfully.
    @MainActor public var readyCount: Int {
        paragraphs.reduce(into: 0) { count, paragraph in
            if paragraph.status == .ready { count += 1 }
        }
    }

    /// Number of paragraphs currently in the failed state.
    @MainActor public var failedCount: Int {
        paragraphs.reduce(into: 0) { count, paragraph in
            if case .failed = paragraph.status { count += 1 }
        }
    }

    /// Total number of paragraphs the runtime is currently tracking.
    @MainActor public var totalCount: Int { paragraphs.count }

    private let translator: Translator
    private let cache: FulltextTranslationCache
    @MainActor public private(set) var maxConcurrency: Int

    @MainActor private var queue: [String] = []
    @MainActor private var tasks: [String: Task<Void, Never>] = [:]
    @MainActor private var generation: Int = 0
    @MainActor private var generationByParagraph: [String: Int] = [:]

    @MainActor
    public init(translator: Translator, cache: FulltextTranslationCache, maxConcurrency: Int = 4) {
        self.translator = translator
        self.cache = cache
        self.maxConcurrency = max(1, maxConcurrency)
    }

    /// Clamp and apply a new concurrency budget; pumps the queue in case the
    /// increased budget unblocks waiting paragraphs.
    @MainActor
    public func setMaxConcurrency(_ newValue: Int) {
        let clamped = max(1, min(8, newValue))
        guard clamped != maxConcurrency else { return }
        maxConcurrency = clamped
        pumpQueue()
    }

    /// Re-queue every paragraph currently in `.failed` state so the worker
    /// picks them up again. Paragraphs in `.ready`, `.queued`, or
    /// `.translating` are untouched — this only affects previously failed
    /// work, matching the Flutter "Retry failed" UX.
    ///
    /// Returns the number of paragraphs that were moved back to the queue.
    @MainActor
    @discardableResult
    public func retryFailedParagraphs() -> Int {
        var requeued = 0
        for index in paragraphs.indices {
            if case .failed = paragraphs[index].status {
                let id = paragraphs[index].id
                tasks[id]?.cancel()
                tasks.removeValue(forKey: id)
                paragraphs[index].status = .queued
                paragraphs[index].translatedText = nil
                generation += 1
                generationByParagraph[id] = generation
                if queue.contains(id) == false {
                    queue.append(id)
                }
                requeued += 1
            }
        }
        if requeued > 0 {
            pumpQueue()
        }
        return requeued
    }

    @MainActor
    public func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        if enabled == false {
            await cancelAll()
        }
    }

    @MainActor
    public func setTargetLanguage(_ language: String) async {
        guard language != targetLanguage else { return }
        targetLanguage = language
        let originals = paragraphs.map { (id: $0.id, text: $0.originalText) }
        paragraphs.removeAll()
        queue.removeAll()
        for (_, task) in tasks { task.cancel() }
        tasks.removeAll()
        inFlightCount = 0
        generationByParagraph.removeAll()
        generation += 1
        await setParagraphs(originals)
    }

    @MainActor
    public func cancelAll() async {
        generation += 1
        for (_, task) in tasks { task.cancel() }
        tasks.removeAll()
        queue.removeAll()
        inFlightCount = 0
        paragraphs.removeAll()
        generationByParagraph.removeAll()
    }

    @MainActor
    public func setParagraphs(_ originals: [(id: String, text: String)]) async {
        let incoming = Set(originals.map { $0.0 })
        // Cancel and remove paragraphs no longer present.
        let removed = paragraphs.map(\.id).filter { incoming.contains($0) == false }
        for id in removed {
            tasks[id]?.cancel()
            tasks.removeValue(forKey: id)
            generationByParagraph.removeValue(forKey: id)
        }
        if removed.isEmpty == false {
            queue.removeAll { removed.contains($0) }
            paragraphs.removeAll { removed.contains($0.id) }
        }

        // Build new paragraph list in incoming order, preserving prior state.
        var byId: [String: Paragraph] = [:]
        for p in paragraphs { byId[p.id] = p }

        var next: [Paragraph] = []
        var needsWork: [(id: String, text: String)] = []
        for (id, text) in originals {
            if let existing = byId[id], existing.originalText == text {
                next.append(existing)
                continue
            }
            // New or changed paragraph — try cache first, else queue.
            if let cached = await cache.lookup(originalText: text, source: sourceLanguage, target: targetLanguage) {
                next.append(Paragraph(id: id, originalText: text, translatedText: cached, status: .ready))
            } else {
                next.append(Paragraph(id: id, originalText: text, translatedText: nil, status: .queued))
                needsWork.append((id, text))
            }
        }
        paragraphs = next

        for (id, _) in needsWork {
            if queue.contains(id) == false, tasks[id] == nil {
                queue.append(id)
                generationByParagraph[id] = generation
            }
        }
        pumpQueue()
    }

    @MainActor
    private func pumpQueue() {
        while inFlightCount < maxConcurrency, let id = queue.first {
            queue.removeFirst()
            guard let index = paragraphs.firstIndex(where: { $0.id == id }) else { continue }
            let text = paragraphs[index].originalText
            let src = sourceLanguage
            let tgt = targetLanguage
            let gen = generationByParagraph[id] ?? generation
            paragraphs[index].status = .translating
            inFlightCount += 1
            let task = Task { [weak self] in
                guard let self else { return }
                await self.runTranslation(id: id, text: text, source: src, target: tgt, generation: gen)
            }
            tasks[id] = task
        }
    }

    private func runTranslation(id: String, text: String, source: String, target: String, generation: Int) async {
        let result: Result<String, Error>
        do {
            let translated = try await translator.translate(text, from: source, to: target)
            result = .success(translated)
        } catch {
            result = .failure(error)
        }
        await MainActor.run { [weak self] in
            guard let self else { return }
            guard let currentGen = self.generationByParagraph[id], currentGen == generation else {
                // Stale — paragraph was evicted or superseded.
                self.tasks.removeValue(forKey: id)
                self.inFlightCount = max(0, self.inFlightCount - 1)
                self.pumpQueue()
                return
            }
            guard let index = self.paragraphs.firstIndex(where: { $0.id == id }) else {
                self.tasks.removeValue(forKey: id)
                self.inFlightCount = max(0, self.inFlightCount - 1)
                self.pumpQueue()
                return
            }
            switch result {
            case .success(let translated):
                self.paragraphs[index].translatedText = translated
                self.paragraphs[index].status = .ready
                let originalText = self.paragraphs[index].originalText
                Task.detached { [cache = self.cache] in
                    await cache.store(originalText: originalText, source: source, target: target, translation: translated)
                }
            case .failure(let error):
                if (error as? CancellationError) != nil {
                    // Silently drop cancellations.
                } else {
                    self.paragraphs[index].status = .failed(message: String(describing: error))
                }
            }
            self.tasks.removeValue(forKey: id)
            self.inFlightCount = max(0, self.inFlightCount - 1)
            self.pumpQueue()
        }
    }
}
