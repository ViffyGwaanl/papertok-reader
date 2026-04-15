import Foundation
import CryptoKit

public actor FulltextTranslationCache {
    private struct Entry: Codable {
        let original: String
        let translation: String
    }

    private let directory: URL
    private var memory: [String: String] = [:]
    private var loadedKeys: Set<String> = []

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base
                .appendingPathComponent("papertok", isDirectory: true)
                .appendingPathComponent("translation-cache", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func lookup(originalText: String, source: String, target: String) -> String? {
        let key = Self.key(text: originalText, source: source, target: target)
        if let cached = memory[key] {
            return cached
        }
        if loadedKeys.contains(key) {
            return nil
        }
        loadedKeys.insert(key)
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let entry = try JSONDecoder().decode(Entry.self, from: data)
            memory[key] = entry.translation
            return entry.translation
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    public func store(originalText: String, source: String, target: String, translation: String) {
        let key = Self.key(text: originalText, source: source, target: target)
        memory[key] = translation
        loadedKeys.insert(key)
        let entry = Entry(original: originalText, translation: translation)
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: fileURL(for: key), options: .atomic)
        }
    }

    public func purge() {
        memory.removeAll()
        loadedKeys.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    static func key(text: String, source: String, target: String) -> String {
        let input = "\(target)|\(source)|\(text)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
