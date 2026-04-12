import Foundation

/// Builds a system-prompt snippet from the user's recent memory files.
///
/// The result is meant to be concatenated into the system message of a ``ChatRequest``
/// so the model has durable context from previous sessions without blowing up token budget.
public struct MemoryContextBuilder: Sendable {
    public init() {}

    /// Produce a bounded block of text summarizing memory from the last `lookbackDays`.
    ///
    /// - Parameters:
    ///   - memoryDirectory: Folder containing `MEMORY.md` and/or `YYYY-MM-DD.md` files.
    ///   - lookbackDays: How many recent daily files to consider.
    ///   - maxChars: Hard cap on the returned string length (including header).
    ///   - now: Injection point for deterministic testing.
    public func buildContext(
        memoryDirectory: URL,
        lookbackDays: Int = 7,
        maxChars: Int = 2000,
        now: Date = Date()
    ) async throws -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: memoryDirectory.path) else { return "" }

        var pieces: [String] = []

        // Long-term memory first (highest priority).
        let longTerm = memoryDirectory.appendingPathComponent("MEMORY.md")
        if fm.fileExists(atPath: longTerm.path),
           let content = try? String(contentsOf: longTerm, encoding: .utf8),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pieces.append("### Long-term memory (MEMORY.md)\n" + content.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Daily memory files newest → oldest, limited to lookbackDays.
        let items = (try? fm.contentsOfDirectory(at: memoryDirectory, includingPropertiesForKeys: nil)) ?? []
        let dailyFormatter = DateFormatter()
        dailyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dailyFormatter.dateFormat = "yyyy-MM-dd"
        let cutoff = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now) ?? now

        var dated: [(Date, URL)] = []
        for item in items where item.pathExtension.lowercased() == "md" {
            let stem = (item.lastPathComponent as NSString).deletingPathExtension
            if stem == "MEMORY" { continue }
            guard let date = dailyFormatter.date(from: stem) else { continue }
            if date < cutoff { continue }
            dated.append((date, item))
        }
        dated.sort { $0.0 > $1.0 }

        for (date, url) in dated {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let label = dailyFormatter.string(from: date)
            pieces.append("### Daily memory — \(label)\n" + trimmed)
        }

        if pieces.isEmpty { return "" }

        let header = "## Persistent memory context\n\n" +
            "The following notes were recorded in previous sessions. Use them to maintain continuity, " +
            "but do not mention them unless relevant to the user's request.\n\n"
        var assembled = header + pieces.joined(separator: "\n\n")
        if assembled.count > maxChars {
            let end = assembled.index(assembled.startIndex, offsetBy: maxChars)
            assembled = String(assembled[..<end]) + "\n…(truncated)"
        }
        return assembled
    }
}
