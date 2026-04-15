import Foundation

/// Actor-isolated LRU cache for re-extracted book content keyed by book +
/// reader context scope. W1.7 AI context resolvers re-extract chapter or
/// whole-book text on every quick action; this cache lets repeat access of
/// the same scope skip the underlying bridge work.
public actor BookContentCache {
    public struct Key: Hashable, Sendable {
        public let bookId: String
        public let scope: Scope

        public init(bookId: String, scope: Scope) {
            self.bookId = bookId
            self.scope = scope
        }

        public enum Scope: Hashable, Sendable {
            case epubChapter(href: String)
            case pdfChapter(startPage: Int, endPage: Int)
            case epubWholeBook
            case pdfWholeBook
            case pdfPage(index: Int)
        }
    }

    private let maxEntries: Int
    private var storage: [Key: String] = [:]
    private var order: [Key] = []

    public init(maxEntries: Int = 64) {
        self.maxEntries = max(1, maxEntries)
    }

    public func get(_ key: Key) -> String? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    public func set(_ key: Key, value: String) {
        if storage[key] != nil {
            storage[key] = value
            touch(key)
            return
        }
        storage[key] = value
        order.append(key)
        while storage.count > maxEntries, let oldest = order.first {
            order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }

    public func clear() {
        storage.removeAll()
        order.removeAll()
    }

    public func count() -> Int {
        storage.count
    }

    private func touch(_ key: Key) {
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
        }
        order.append(key)
    }
}
