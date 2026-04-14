import Foundation
import PTCore

/// Generates short digests of chat conversations and appends them to daily memory files.
///
/// Intended to be called at the end of a session (or on a timer) so that long conversations
/// can be compressed into a persistent, searchable record without bloating the live context.
public actor SessionDigestService {
    public enum DigestError: LocalizedError {
        case emptyMessages
        case providerReturnedEmpty
        case memoryDirectoryUnavailable

        public var errorDescription: String? {
            switch self {
            case .emptyMessages:
                return AppLocalization.string(
                    "errors.memory.digest.no_messages",
                    value: "No messages are available to summarize."
                )
            case .providerReturnedEmpty:
                return AppLocalization.string("errors.ai.no_response")
            case .memoryDirectoryUnavailable:
                return AppLocalization.string(
                    "errors.memory.digest.directory_unavailable",
                    value: "Couldn't access the memory folder."
                )
            }
        }
    }

    private let model: String
    private let maxWords: Int
    private let dateFormatter: DateFormatter

    public init(model: String = "gpt-4o-mini", maxWords: Int = 200) {
        self.model = model
        self.maxWords = maxWords
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        self.dateFormatter = fmt
    }

    /// Produce a short digest for the given messages using the supplied provider.
    public func digest(
        messages: [ChatMessage],
        provider: any ChatModelProvider,
        now: Date = Date()
    ) async throws -> String {
        guard !messages.isEmpty else { throw DigestError.emptyMessages }

        let transcript = Self.formatTranscript(messages: messages)
        let systemPrompt = """
        You are a memory summarizer. Produce a concise digest (maximum \(maxWords) words) of
        the following conversation. Focus on: user goals, decisions made, facts learned about
        the user, open tasks, and any durable context worth remembering later. Write in
        neutral third-person past tense. Do not include pleasantries. Output plain text only.
        """

        let request = ChatRequest(
            messages: [
                .system(systemPrompt),
                .user(transcript),
            ],
            model: model,
            temperature: 0.2,
            maxTokens: 600
        )
        let response = try await provider.complete(request)
        let text = (response.message.textContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DigestError.providerReturnedEmpty }
        return text
    }

    /// Generate a digest and append it to the daily memory file (YYYY-MM-DD.md).
    /// Returns the digest string.
    @discardableResult
    public func digestAndAppend(
        messages: [ChatMessage],
        provider: any ChatModelProvider,
        memoryDirectory: URL,
        now: Date = Date()
    ) async throws -> String {
        let text = try await digest(messages: messages, provider: provider, now: now)
        try Self.ensureDirectory(memoryDirectory)

        let filename = dateFormatter.string(from: now) + ".md"
        let fileURL = memoryDirectory.appendingPathComponent(filename)

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.dateFormat = "HH:mm"
        let header = "\n\n## Session digest \(timeFmt.string(from: now))\n\n"
        let block = header + text + "\n"

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            try (existing + block).write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            let title = "# Daily memory — \(dateFormatter.string(from: now))\n"
            try (title + block).write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return text
    }

    // MARK: - Helpers

    private static func ensureDirectory(_ url: URL) throws {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private static func formatTranscript(messages: [ChatMessage]) -> String {
        var lines: [String] = []
        for message in messages {
            let role: String
            switch message.role {
            case .system: role = "System"
            case .user: role = "User"
            case .assistant: role = "Assistant"
            case .tool: role = "Tool"
            }
            let text = message.textContent ?? ""
            if text.isEmpty { continue }
            lines.append("\(role): \(text)")
        }
        return lines.joined(separator: "\n")
    }
}
