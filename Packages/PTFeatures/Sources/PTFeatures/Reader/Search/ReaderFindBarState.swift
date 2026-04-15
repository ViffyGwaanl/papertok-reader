import Foundation
import Observation
import PTReader

/// Shared observable state for the reader find bar. Drives both EPUB and PDF
/// reader hosts so the UI code lives in a single `ReaderFindBar` view.
@MainActor
@Observable
public final class ReaderFindBarState {
    public typealias SearchProvider = @MainActor (String) async throws -> [ReaderSearchHit]

    public var query: String = ""
    public private(set) var isSearching: Bool = false
    public private(set) var hits: [ReaderSearchHit] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var hasSearched: Bool = false
    public private(set) var errorMessage: String?

    /// Debounce interval applied by `scheduleSubmit(query:)`. Exposed for tests.
    public let debounceInterval: Duration

    private let provider: SearchProvider
    private var activeTask: Task<Void, Never>?

    public init(
        debounceInterval: Duration = .milliseconds(300),
        provider: @escaping SearchProvider
    ) {
        self.debounceInterval = debounceInterval
        self.provider = provider
    }

    public var currentHit: ReaderSearchHit? {
        guard hits.indices.contains(currentIndex) else { return nil }
        return hits[currentIndex]
    }

    public var hasNoResults: Bool {
        hasSearched && hits.isEmpty && !isSearching && trimmed(query).isEmpty == false
    }

    /// Debounced wrapper around `submit`. The most recent call wins; pending
    /// calls are cancelled if a new query arrives inside the debounce window.
    public func scheduleSubmit(query: String) {
        startSubmit(query: query, debounce: debounceInterval)
    }

    /// Run a search immediately, bypassing the debounce. Empty queries clear
    /// state. Routes through the shared cancellable task slot so concurrent
    /// callers cannot interleave — the most recent submission always wins.
    public func submit(query: String) async {
        let task = startSubmit(query: query, debounce: .zero)
        await task.value
    }

    @discardableResult
    private func startSubmit(query: String, debounce: Duration) -> Task<Void, Never> {
        self.query = query
        activeTask?.cancel()
        let provider = self.provider
        let task = Task { [weak self] in
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
            }
            if Task.isCancelled { return }
            await self?.runSubmit(query: query, provider: provider)
        }
        activeTask = task
        return task
    }

    private func runSubmit(
        query: String,
        provider: SearchProvider
    ) async {
        let trimmedQuery = trimmed(query)
        self.query = query

        guard trimmedQuery.isEmpty == false else {
            clearResults()
            return
        }

        isSearching = true
        errorMessage = nil
        defer {
            if Task.isCancelled == false {
                isSearching = false
            }
        }

        do {
            let results = try await provider(trimmedQuery)
            if Task.isCancelled { return }
            hits = results
            currentIndex = 0
            hasSearched = true
        } catch is CancellationError {
            // Swallow cancellations so a replaced search doesn't surface errors.
        } catch {
            if Task.isCancelled { return }
            hits = []
            currentIndex = 0
            hasSearched = true
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    public func next() {
        guard hits.isEmpty == false else { return }
        currentIndex = (currentIndex + 1) % hits.count
    }

    public func previous() {
        guard hits.isEmpty == false else { return }
        currentIndex = (currentIndex - 1 + hits.count) % hits.count
    }

    public func select(index: Int) {
        guard hits.indices.contains(index) else { return }
        currentIndex = index
    }

    /// Fully reset the bar: cancels any pending debounce, clears query, hits
    /// and the "has searched" flag. Host should use this when the bar closes.
    public func clear() {
        activeTask?.cancel()
        activeTask = nil
        query = ""
        hits = []
        currentIndex = 0
        isSearching = false
        hasSearched = false
        errorMessage = nil
    }

    private func clearResults() {
        hits = []
        currentIndex = 0
        hasSearched = false
        errorMessage = nil
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
